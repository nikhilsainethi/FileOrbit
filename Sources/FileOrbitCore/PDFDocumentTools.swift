import Foundation
import CoreGraphics
import PDFKit
import ImageIO
import Vision
import zlib

/// Real local document operations. All files remain inside the engine's private staging folder.
enum PDFDocumentTools {
    static let maximumRenderPixels = 32_000_000
    static let maximumMergedHeight = 32_768

    static func displayedSize(_ page: PDFPage) throws -> CGSize {
        guard let reference = page.pageRef else { throw ConversionError.invalidInput("The PDF contains an unreadable page.") }
        let box = reference.getBoxRect(.cropBox)
        let rotated = abs(reference.rotationAngle) % 180 == 90
        let size = CGSize(width: rotated ? box.height : box.width, height: rotated ? box.width : box.height)
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
              size.width <= 10_000_000, size.height <= 10_000_000 else {
            throw ConversionError.invalidInput("The PDF contains an invalid or excessively large page.")
        }
        return size
    }

    static func render(_ page: PDFPage, scale requestedScale: CGFloat = 2, pixelLimit: Int = maximumRenderPixels,
                       regions: [CGRect] = []) throws -> CGImage {
        let size = try displayedSize(page)
        let scale = min(requestedScale, 8192 / max(size.width, size.height), sqrt(CGFloat(pixelLimit) / (size.width * size.height)))
        let width = max(1, Int(floor(size.width * scale))), height = max(1, Int(floor(size.height * scale)))
        let context = try bitmap(width: width, height: height)
        context.saveGState()
        context.scaleBy(x: CGFloat(width) / size.width, y: CGFloat(height) / size.height)
        page.displaysAnnotations = true
        page.draw(with: .cropBox, to: context)
        context.restoreGState()
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.setShouldAntialias(false)
        for rect in regions {
            // Cover boundary pixels outward so no subpixel edge of the selected content remains.
            let left = floor(rect.minX * CGFloat(width)), right = ceil(rect.maxX * CGFloat(width))
            let bottom = floor((1 - rect.maxY) * CGFloat(height)), top = ceil((1 - rect.minY) * CGFloat(height))
            context.fill(CGRect(x: left, y: bottom, width: right - left, height: top - bottom))
        }
        guard let image = context.makeImage() else { throw ConversionError.failed("Could not render the PDF page.") }
        return image
    }

    static func bitmap(width: Int, height: Int) throws -> CGContext {
        guard width > 0, height > 0, width <= maximumRenderPixels / height,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
            throw ConversionError.unsupported("The rendered image exceeds the 32-megapixel limit.")
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context
    }

    static func export(input: URL, format: OutputFormat, mode: PDFExportMode, workspace: URL, cancellation: CancellationToken, environment: EngineEnvironment = EngineEnvironment()) throws -> [URL] {
        guard format == .png || format == .jpg || format == .webp else { throw ConversionError.unsupported("PDF image export supports PNG, JPEG and WebP.") }
        let document = try NativeConverter.readablePDF(input)
        guard document.allowsPrinting else { throw ConversionError.unsupported("This PDF does not allow page rendering.") }
        try cancellation.check()
        if mode == .mergedTallImage { return [try merged(document, format: format, workspace: workspace, cancellation: cancellation, environment: environment)] }
        let count = mode == .firstPage ? 1 : document.pageCount
        var outputs: [URL] = []
        for index in 0..<count {
            try cancellation.check()
            let url: URL = try autoreleasepool {
                guard let page = document.page(at: index) else { throw ConversionError.failed("Could not read PDF page \(index + 1).") }
                let image = try render(page)
                let output = workspace.appendingPathComponent(String(format: "page-%04d.%@", index + 1, format.rawValue))
                try OutputEncoder.encode(image, to: output, format: format, environment: environment, cancellation: cancellation)
                return output
            }
            outputs.append(url)
        }
        try cancellation.check()
        return outputs
    }

    private static func merged(_ document: PDFDocument, format: OutputFormat, workspace: URL, cancellation: CancellationToken, environment: EngineEnvironment) throws -> URL {
        let sizes = try (0..<document.pageCount).map { index -> CGSize in
            guard let page = document.page(at: index) else { throw ConversionError.invalidInput("The PDF contains an unreadable page.") }
            return try displayedSize(page)
        }
        let maxWidth = sizes.map(\.width).max()!, totalHeight = sizes.reduce(0) { $0 + $1.height }
        let heightLimit = format == .webp ? 16_383 : maximumMergedHeight
        let scale = min(2, 8192 / maxWidth, CGFloat(heightLimit) / totalHeight,
                        sqrt(CGFloat(maximumRenderPixels) / (maxWidth * totalHeight)))
        let widths = sizes.map { max(1, Int(floor($0.width * scale))) }
        let heights = sizes.map { max(1, Int(floor($0.height * scale))) }
        let width = widths.max()!, height = heights.reduce(0, +)
        guard height <= heightLimit else { throw ConversionError.unsupported("These pages cannot fit within the merged-image size limit.") }
        let context = try bitmap(width: width, height: height)
        var top = height
        for index in 0..<document.pageCount {
            try cancellation.check()
            try autoreleasepool {
                guard let page = document.page(at: index) else { throw ConversionError.failed("Could not read PDF page \(index + 1).") }
                top -= heights[index]
                context.saveGState()
                context.translateBy(x: CGFloat(width - widths[index]) / 2, y: CGFloat(top))
                context.clip(to: CGRect(x: 0, y: 0, width: widths[index], height: heights[index]))
                context.scaleBy(x: CGFloat(widths[index]) / sizes[index].width, y: CGFloat(heights[index]) / sizes[index].height)
                page.displaysAnnotations = true; page.draw(with: .cropBox, to: context)
                context.restoreGState()
            }
        }
        guard let image = context.makeImage() else { throw ConversionError.failed("Could not assemble the PDF pages.") }
        let output = workspace.appendingPathComponent("pages-merged.\(format.rawValue)")
        try cancellation.check()
        try OutputEncoder.encode(image, to: output, format: format, environment: environment, cancellation: cancellation)
        return output
    }

    static func split(input: URL, workspace: URL, cancellation: CancellationToken) throws -> [URL] {
        let original = try PDFSafety.modifiableDocument(input)
        var outputs: [URL] = []
        for index in 0..<original.pageCount {
            try cancellation.check()
            let output: URL = try autoreleasepool {
                guard let page = original.page(at: index)?.copy() as? PDFPage else { throw ConversionError.failed("Could not read PDF page \(index + 1).") }
                let document = PDFDocument(); document.insert(page, at: 0)
                let url = workspace.appendingPathComponent(String(format: "page-%04d.pdf", index + 1))
                guard document.write(to: url), let check = PDFDocument(url: url), check.pageCount == 1,
                      check.string == document.string else { throw ConversionError.failed("A split page failed validation.") }
                return url
            }
            outputs.append(output)
        }
        return outputs
    }

    static func redact(input: URL, regions: [RedactionRegion], workspace: URL, cancellation: CancellationToken) throws -> [URL] {
        let document = try PDFSafety.modifiableDocument(input)
        guard document.allowsPrinting else { throw ConversionError.unsupported("This PDF does not allow page rendering.") }
        guard !regions.isEmpty, regions.count <= 10_000 else { throw ConversionError.invalidInput("Draw at least one region to redact (up to 10,000 regions).") }
        for region in regions {
            let rect = region.normalizedRect
            guard (0..<document.pageCount).contains(region.pageIndex),
                  [rect.origin.x, rect.origin.y, rect.width, rect.height].allSatisfy(\.isFinite),
                  rect.width > 0, rect.height > 0, rect.minX >= 0, rect.minY >= 0, rect.maxX <= 1, rect.maxY <= 1 else {
                throw ConversionError.invalidInput("A redaction region falls outside its displayed PDF page.")
            }
        }
        let grouped = Dictionary(grouping: regions, by: \.pageIndex)
        let output = workspace.appendingPathComponent("redacted.pdf")
        let writer = try RasterPDFWriter(url: output, pageCount: document.pageCount)
        for index in 0..<document.pageCount {
            try cancellation.check()
            try autoreleasepool {
                guard let page = document.page(at: index) else { throw ConversionError.failed("Could not read PDF page \(index + 1).") }
                let image = try render(page, pixelLimit: 16_000_000, regions: grouped[index]?.map(\.normalizedRect) ?? [])
                try writer.append(image: image, size: displayedSize(page), cancellation: cancellation)
            }
        }
        try cancellation.check(); try writer.finish()
        guard let check = PDFDocument(url: output), check.pageCount == document.pageCount,
              (check.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let reference = CGPDFDocument(output as CFURL), reference.info == nil else {
            throw ConversionError.failed("The redacted PDF failed its content-removal checks.")
        }
        return [output]
    }

    static func ocr(input: URL, workspace: URL, cancellation: CancellationToken) throws -> [URL] {
        var pages: [String] = []
        if FileKind.detect(input) == .pdf {
            let document = try NativeConverter.readablePDF(input)
            guard document.allowsCopying, document.allowsPrinting else { throw ConversionError.unsupported("This PDF does not allow text extraction or page rendering.") }
            for index in 0..<document.pageCount {
                try cancellation.check()
                pages.append(try autoreleasepool {
                    guard let page = document.page(at: index) else { throw ConversionError.invalidInput("The PDF contains an unreadable page.") }
                    return try recognize(render(page, pixelLimit: 16_000_000), cancellation: cancellation)
                })
            }
        } else if FileKind.detect(input) == .image {
            try cancellation.check()
            pages = [try recognize(NativeConverter.decodedImage(input, maxDimension: 4096), cancellation: cancellation)]
        } else { throw ConversionError.unsupported("OCR supports images and PDF documents.") }
        try cancellation.check()
        let text = pages.joined(separator: "\n\u{000C}\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)).isEmpty else {
            throw ConversionError.unsupported("No readable text was recognized. No empty text file was saved.")
        }
        let output = workspace.appendingPathComponent("recognized-text.txt")
        try text.write(to: output, atomically: true, encoding: .utf8)
        return [output]
    }

    private static func recognize(_ image: CGImage, cancellation: CancellationToken) throws -> String {
        try cancellation.check()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate; request.usesLanguageCorrection = true; request.automaticallyDetectsLanguage = true
        request.progressHandler = { request, _, _ in if cancellation.isCancelled { request.cancel() } }
        do { try VNImageRequestHandler(cgImage: image, options: [:]).perform([request]) }
        catch { try cancellation.check(); throw ConversionError.failed("Local text recognition failed: \(error.localizedDescription)") }
        try cancellation.check()
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}

/// Writes only losslessly compressed RGB pixels and page geometry. It never imports source PDF
/// objects, text, annotations, attachments, actions, or metadata, including on unmarked pages.
final class RasterPDFWriter {
    private let file: FileHandle
    private let pageCount: Int
    private var offsets: [UInt64]
    private var pagesWritten = 0
    init(url: URL, pageCount: Int) throws {
        self.pageCount = pageCount; self.offsets = Array(repeating: 0, count: 3 + pageCount * 3)
        guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw ConversionError.failed("Could not create the redacted PDF.") }
        file = try FileHandle(forWritingTo: url)
        try write("%PDF-1.7\n%FileOrbit raster document\n")
    }
    deinit { try? file.close() }
    private func write(_ string: String) throws { try file.write(contentsOf: Data(string.utf8)) }
    private func beginObject(_ number: Int) throws { offsets[number] = try file.offset(); try write("\(number) 0 obj\n") }
    func append(image: CGImage, size: CGSize, cancellation: CancellationToken) throws {
        guard pagesWritten < pageCount else { throw ConversionError.failed("Unexpected redaction page count.") }
        let bitmap = try PDFDocumentTools.bitmap(width: image.width, height: image.height)
        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let pixels = bitmap.data?.assumingMemoryBound(to: UInt8.self) else { throw ConversionError.failed("Could not read redacted pixels.") }
        var rgb = Data(count: image.width * image.height * 3)
        try rgb.withUnsafeMutableBytes { raw in
            let target = raw.bindMemory(to: UInt8.self)
            for row in 0..<image.height {
                if row % 128 == 0 { try cancellation.check() }
                for column in 0..<image.width {
                    let source = (row * image.width + column) * 4, destination = (row * image.width + column) * 3
                    target[destination] = pixels[source]; target[destination + 1] = pixels[source + 1]; target[destination + 2] = pixels[source + 2]
                }
            }
        }
        var length = compressBound(uLong(rgb.count)), compressed = Data(count: Int(compressBound(uLong(rgb.count))))
        let result = compressed.withUnsafeMutableBytes { destination in
            rgb.withUnsafeBytes { source in compress2(destination.bindMemory(to: Bytef.self).baseAddress!, &length, source.bindMemory(to: Bytef.self).baseAddress!, uLong(rgb.count), Z_DEFAULT_COMPRESSION) }
        }
        guard result == Z_OK else { throw ConversionError.failed("Could not encode redacted page pixels.") }
        compressed.count = Int(length); try cancellation.check()
        let page = 3 + pagesWritten * 3, imageNumber = page + 1, content = page + 2
        try beginObject(page)
        try write("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 \(size.width) \(size.height)] /Resources << /XObject << /Im \(imageNumber) 0 R >> >> /Contents \(content) 0 R >>\nendobj\n")
        try beginObject(imageNumber)
        try write("<< /Type /XObject /Subtype /Image /Width \(image.width) /Height \(image.height) /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode /Length \(compressed.count) >>\nstream\n")
        try file.write(contentsOf: compressed); try write("\nendstream\nendobj\n")
        let commands = "q \(size.width) 0 0 \(size.height) 0 0 cm /Im Do Q\n"
        try beginObject(content); try write("<< /Length \(commands.utf8.count) >>\nstream\n\(commands)endstream\nendobj\n")
        pagesWritten += 1
    }
    func finish() throws {
        guard pagesWritten == pageCount else { throw ConversionError.failed("Not all redacted pages were written.") }
        try beginObject(1); try write("<< /Type /Catalog /Pages 2 0 R >>\nendobj\n")
        try beginObject(2)
        let kids = (0..<pageCount).map { "\(3 + $0 * 3) 0 R" }.joined(separator: " ")
        try write("<< /Type /Pages /Count \(pageCount) /Kids [\(kids)] >>\nendobj\n")
        let xref = try file.offset()
        try write("xref\n0 \(offsets.count)\n0000000000 65535 f \n")
        for offset in offsets.dropFirst() { try write(String(format: "%010llu 00000 n \n", offset)) }
        try write("trailer\n<< /Size \(offsets.count) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n")
        try file.synchronize(); try file.close()
    }
}
