import Foundation
import ImageIO
import CoreGraphics
import PDFKit

public struct ConversionEngine: Sendable {
    public let environment: EngineEnvironment
    public init(environment: EngineEnvironment) { self.environment = environment }

    /// Runs off the UI thread. The original is opened read-only and all intermediate output is private.
    public func run(_ request: ConversionRequest, cancellation: CancellationToken = CancellationToken()) throws -> ConversionResult {
        try cancellation.check()
        guard request.input.isFileURL else { throw ConversionError.invalidInput("Choose a local file to process.") }
        let input = request.input.standardizedFileURL
        let values = try input.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw ConversionError.invalidInput("Select a regular file, rather than a folder, alias or symbolic link.")
        }
        let inputBytes = Int64(values.fileSize ?? 0)
        guard inputBytes > 0, inputBytes <= 1_073_741_824 else {
            throw ConversionError.unsupported("Files must be nonempty and no larger than 1 GB in this release.")
        }
        let kind = FileKind.detect(input)
        guard kind != .unsupported else { throw ConversionError.unsupported("This file type is not supported yet.") }
        let directory = (request.outputDirectory ?? input.deletingLastPathComponent()).standardizedFileURL
        guard directory.isFileURL,
              (try directory.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true else {
            throw ConversionError.invalidInput("Choose an existing local folder for the result.")
        }
        // Staging beside the output guarantees an atomic same-volume final rename.
        let workspace = directory.appendingPathComponent(".fileorbit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: workspace) }
        let files: [URL]
        let compressed: Bool
        let note: String?
        switch request.operation {
        case .convert(let format):
            compressed = false
            switch kind {
            case .image:
                files = try NativeConverter.convert(input: input, to: format, workspace: workspace, cancellation: cancellation)
                note = format == .jpg ? "Transparent areas use a white background. Image metadata may change." : "Image metadata may change during conversion."
            case .pdf:
                files = try NativeConverter.convertPDF(input: input, to: format, workspace: workspace, cancellation: cancellation)
                note = format == .txt ? "Extracted the existing text layer; reading order follows the PDF." : "Pages rendered at up to 144 DPI (8,192 pixels per side / 32 megapixels per page)."
            case .docx, .pptx, .text:
                files = try OfficeConverter.convert(input: input, to: format, workspace: workspace, environment: environment, cancellation: cancellation)
                note = "Converted locally with LibreOffice. Fonts and complex layouts can differ from Microsoft Office."
            case .svg:
                files = try convertSVG(input: input, format: format, workspace: workspace, cancellation: cancellation)
                note = "Static SVG rendered to pixels, up to 2,048 pixels per side."
            case .unsupported: throw ConversionError.unsupported("This file type is not supported yet.")
            }
        case .compress(let preset):
            compressed = true
            switch kind {
            case .image:
                files = try NativeConverter.compress(input: input, preset: preset, workspace: workspace, cancellation: cancellation)
                note = "Image dimensions and encoding quality may be reduced. Metadata may change."
            case .pdf:
                files = try compressPDF(input: input, preset: preset, workspace: workspace, cancellation: cancellation)
                note = preset == .gentle ? "Optimized PDF structure without reducing image quality." : "Optimized PDF structure and eligible embedded images; text and vectors remain intact."
            case .docx:
                files = try DocxCompressor.compress(input: input, preset: preset, workspace: workspace, cancellation: cancellation)
                note = "Optimized embedded raster images. Document XML and image relationships are preserved."
            default: throw ConversionError.unsupported("Compression is available for images, PDF and DOCX files.")
            }
        }
        try cancellation.check()
        let outputBytes = try validate(files: files, workspace: workspace)
        if compressed, outputBytes >= inputBytes { throw ConversionError.notSmaller }
        try cancellation.check()
        let published = try OutputPublisher.publish(files: files, source: input, directory: directory, compressed: compressed)
        // Once atomic publication succeeds, the completed result wins over a simultaneous late Cancel.
        return ConversionResult(outputURLs: published, inputBytes: inputBytes, outputBytes: outputBytes, note: note)
    }

    private func validate(files: [URL], workspace: URL) throws -> Int64 {
        guard !files.isEmpty, files.count <= NativeConverter.maximumPDFPages else {
            throw ConversionError.failed("The converter returned an invalid number of outputs.")
        }
        let prefix = workspace.resolvingSymlinksInPath().path + "/"
        var total: Int64 = 0
        for file in files {
            guard file.resolvingSymlinksInPath().path.hasPrefix(prefix) else { throw ConversionError.failed("A converter returned an invalid output location.") }
            let properties = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard properties.isRegularFile == true, properties.isSymbolicLink != true, let count = properties.fileSize, count > 0 else {
                throw ConversionError.failed("The converter produced an empty or invalid file.")
            }
            total += Int64(count)
            switch file.pathExtension.lowercased() {
            case "png", "jpg", "jpeg", "heic", "tiff":
                guard let source = CGImageSourceCreateWithURL(file as CFURL, nil), CGImageSourceGetCount(source) == 1,
                      CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
                    throw ConversionError.failed("The output image could not be reopened.")
                }
            case "pdf":
                guard let document = PDFDocument(url: file), document.pageCount > 0 else { throw ConversionError.failed("The output PDF could not be reopened.") }
            case "txt":
                guard String(data: try Data(contentsOf: file), encoding: .utf8) != nil else { throw ConversionError.failed("The output text is not valid UTF-8.") }
            case "docx":
                let handle = try FileHandle(forReadingFrom: file)
                defer { try? handle.close() }
                guard try handle.read(upToCount: 4) == Data([0x50, 0x4b, 0x03, 0x04]) else { throw ConversionError.failed("The output DOCX package is invalid.") }
            default: throw ConversionError.failed("The converter produced an unexpected file type.")
            }
        }
        return total
    }

    private func compressPDF(input: URL, preset: CompressionPreset, workspace: URL, cancellation: CancellationToken) throws -> [URL] {
        guard let qpdf = environment.qpdfURL else { throw ConversionError.missingDependency("Install qpdf to enable local PDF compression.") }
        let original = try NativeConverter.readablePDF(input)
        let signatureWidget = (0..<original.pageCount).contains { index in
            original.page(at: index)?.annotations.contains { $0.widgetFieldType == .signature } == true
        }
        guard !signatureWidget, !hasSignature(input) else {
            throw ConversionError.unsupported("This PDF is signed or contains signature fields. Compression could invalidate a signature, so the original is unchanged.")
        }
        let output = workspace.appendingPathComponent("compressed.pdf")
        var args = ["--object-streams=generate", "--stream-data=compress", "--recompress-flate", "--compression-level=9"]
        if preset != .gentle { args += ["--optimize-images", "--jpeg-quality=\(preset == .balanced ? 82 : 62)"] }
        args += [input.path, output.path]
        _ = try LocalProcess.run(executable: qpdf, arguments: args, timeout: 180, cancellation: cancellation, directory: workspace)
        _ = try LocalProcess.run(executable: qpdf, arguments: ["--check", output.path], timeout: 30, cancellation: cancellation, directory: workspace)
        guard let result = PDFDocument(url: output), result.pageCount == original.pageCount,
              result.string == original.string else {
            throw ConversionError.failed("The compressed PDF did not preserve its pages and text. No output was saved.")
        }
        return [output]
    }

    private func hasSignature(_ input: URL) -> Bool {
        guard let pdf = CGPDFDocument(input as CFURL), let catalog = pdf.catalog else { return true }
        var permissions: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(catalog, "Perms", &permissions) { return true }
        var form: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(catalog, "AcroForm", &form), let form else { return false }
        var fields: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(form, "Fields", &fields), let fields else { return false }
        return signedField(in: fields, depth: 0)
    }

    private func signedField(in fields: CGPDFArrayRef, depth: Int) -> Bool {
        guard depth < 32 else { return true }
        for index in 0..<CGPDFArrayGetCount(fields) {
            var field: CGPDFDictionaryRef?
            guard CGPDFArrayGetDictionary(fields, index, &field), let field else { continue }
            var name: UnsafePointer<CChar>?
            if CGPDFDictionaryGetName(field, "FT", &name), let name, String(cString: name) == "Sig" { return true }
            var children: CGPDFArrayRef?
            if CGPDFDictionaryGetArray(field, "Kids", &children), let children, signedField(in: children, depth: depth + 1) { return true }
        }
        return false
    }

    private func convertSVG(input: URL, format: OutputFormat, workspace: URL, cancellation: CancellationToken) throws -> [URL] {
        guard format == .png || format == .jpg else { throw ConversionError.unsupported("SVG can be rendered to PNG or JPEG.") }
        guard let resvg = environment.resvgURL else { throw ConversionError.missingDependency("Install resvg to render SVG files locally.") }
        let data = try Data(contentsOf: input)
        guard data.count <= 16 * 1024 * 1024 else { throw ConversionError.unsupported("SVG files must be smaller than 16 MB.") }
        let dimensions = try SVGPreflight.validate(data)
        let snapshot = workspace.appendingPathComponent("validated.svg")
        try data.write(to: snapshot, options: .atomic)
        let png = workspace.appendingPathComponent("render.png")
        _ = try LocalProcess.run(executable: resvg, arguments: ["--width", "\(dimensions.0)", "--height", "\(dimensions.1)", "--resources-dir", workspace.path, snapshot.path, png.path], timeout: 90, cancellation: cancellation, directory: workspace)
        let image = try NativeConverter.decodedImage(png)
        guard image.width <= 2048, image.height <= 2048 else { throw ConversionError.failed("The SVG renderer exceeded the requested image dimensions.") }
        if format == .png { return [png] }
        let jpeg = workspace.appendingPathComponent("render.jpg")
        try NativeConverter.encode(image, to: jpeg, format: .jpg, quality: 0.92)
        return [jpeg]
    }
}

/// Static, self-contained SVG only: avoid scripts, entity expansion and linked resources.
private final class SVGPreflight: NSObject, XMLParserDelegate {
    private var failure: String?
    private var rootSeen = false
    private var dimensions = (300.0, 150.0)
    private var inStyle = false
    private var stylesheet = ""
    static func validate(_ data: Data) throws -> (Int, Int) {
        guard let text = String(data: data, encoding: .utf8) else { throw ConversionError.unsupported("SVG files must use UTF-8 encoding.") }
        guard text.range(of: "<!DOCTYPE", options: .caseInsensitive) == nil,
              text.range(of: "<!ENTITY", options: .caseInsensitive) == nil,
              text.range(of: "@import", options: .caseInsensitive) == nil else {
            throw ConversionError.unsupported("SVG entities, document types and external stylesheets are not supported.")
        }
        // CSS url() references may be local fragment identifiers or embedded raster images only.
        let expression = try NSRegularExpression(pattern: "url\\s*\\(\\s*['\"]?([^)'\"]+)", options: [.caseInsensitive])
        for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let range = Range(match.range(at: 1), in: text), !allowedReference(String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)) {
                throw ConversionError.unsupported("SVG linked resources are not supported. Embed the image or use a self-contained SVG.")
            }
        }
        let validator = SVGPreflight()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = validator
        guard parser.parse(), validator.rootSeen, validator.failure == nil else {
            throw ConversionError.invalidInput(validator.failure ?? "This SVG is not valid XML.")
        }
        let (width, height) = validator.dimensions
        guard width.isFinite, height.isFinite, width > 0, height > 0, width <= 1e9, height <= 1e9 else {
            throw ConversionError.invalidInput("The SVG has invalid dimensions.")
        }
        let scale = min(1, 2048 / max(width, height))
        return (max(1, Int((width * scale).rounded())), max(1, Int((height * scale).rounded())))
    }
    static func allowedReference(_ value: String) -> Bool {
        let value = value.lowercased()
        return value.hasPrefix("#") || value.hasPrefix("data:image/png;") || value.hasPrefix("data:image/jpeg;") || value.hasPrefix("data:image/webp;")
    }
    static func safeCSS(_ value: String) -> Bool {
        guard !value.contains("\\"), value.range(of: "@import", options: .caseInsensitive) == nil,
              let regex = try? NSRegularExpression(pattern: "url\\s*\\(\\s*['\"]?([^)'\"]+)", options: [.caseInsensitive]) else { return false }
        return regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).allSatisfy {
            guard let range = Range($0.range(at: 1), in: value) else { return false }
            return allowedReference(String(value[range]).trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributesDict: [String: String] = [:]) {
        let element = elementName.split(separator: ":").last.map(String.init)?.lowercased() ?? ""
        if !rootSeen {
            guard element == "svg" else { failure = "The document root is not SVG."; parser.abortParsing(); return }
            rootSeen = true
            let box = attributesDict["viewBox"]?.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\t" || $0 == "\n" }).compactMap { Double($0) }
            if let box, box.count == 4 { dimensions = (box[2], box[3]) }
            func pixels(_ value: String?) -> Double? {
                guard let value else { return nil }
                return Double(value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "px", with: ""))
            }
            if let width = pixels(attributesDict["width"]) { dimensions.0 = width }
            if let height = pixels(attributesDict["height"]) { dimensions.1 = height }
        }
        if ["script", "animate", "animatetransform", "animatemotion", "set", "foreignobject"].contains(element) {
            failure = "Only static SVG is supported; scripts, animations and embedded HTML are not rendered."; parser.abortParsing(); return
        }
        if element == "style" { inStyle = true; stylesheet = "" }
        for (key, value) in attributesDict {
            let name = key.split(separator: ":").last.map(String.init)?.lowercased() ?? ""
            if (name == "href" && !Self.allowedReference(value)) || key.lowercased().hasPrefix("on") || !Self.safeCSS(value) {
                failure = "SVG linked resources and scripted events are not supported. Use a self-contained static SVG."
                parser.abortParsing(); return
            }
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if inStyle { stylesheet += string } }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if inStyle { stylesheet += String(data: CDATABlock, encoding: .utf8) ?? "\\" }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName.split(separator: ":").last?.lowercased() == "style" {
            if !Self.safeCSS(stylesheet) {
                failure = "SVG stylesheets must be self-contained and cannot use escaped or external resource references."
                parser.abortParsing()
            }
            inStyle = false; stylesheet = ""
        }
    }
    func parser(_ parser: XMLParser, foundProcessingInstructionWithTarget target: String, data: String?) {
        if target.lowercased() == "xml-stylesheet" {
            failure = "External SVG stylesheets are not supported."
            parser.abortParsing()
        }
    }
}
