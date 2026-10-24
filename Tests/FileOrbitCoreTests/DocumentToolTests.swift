import Testing
import Foundation
import ImageIO
import CoreGraphics
import CoreText
import PDFKit
import AppKit
@testable import FileOrbitCore

@Suite(.serialized)
final class DocumentToolTests {
    let folder: URL
    let engine = ConversionEngine(environment: EngineEnvironment.discover())
    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("fileorbit-document-tools-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: folder) }

    func pdf(pages: Int = 2) throws -> URL {
        let url = folder.appendingPathComponent("document.pdf")
        var box = CGRect(x: 0, y: 0, width: 300, height: 200)
        let metadata = [kCGPDFContextAuthor: "PRIVATE AUTHOR", kCGPDFContextTitle: "PRIVATE TITLE"] as CFDictionary
        let context = try #require(CGContext(url as CFURL, mediaBox: &box, metadata))
        for index in 1...pages {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(box)
            context.setFillColor(CGColor(red: index == 1 ? 1 : 0, green: index == 1 ? 0 : 1, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 25, height: 25))
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: "ORBIT SECRET \(index)", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 24, nil)]))
            context.textPosition = CGPoint(x: 20, y: 140); CTLineDraw(line, context)
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }
    func destination() throws -> URL {
        let url = folder.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func image(_ url: URL) throws -> CGImage {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }
    func rgba(_ image: CGImage) throws -> [UInt8] {
        let context = try #require(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self), count: image.width * image.height * 4))
    }

    @Test func exportModesHaveRealPageDimensionsAndKeepSource() throws {
        let input = try pdf(); let original = try Data(contentsOf: input)
        let first = try engine.run(.init(input: input, operation: .exportPDF(.png, .firstPage), outputDirectory: destination()))
        let all = try engine.run(.init(input: input, operation: .exportPDF(.jpg, .allPages), outputDirectory: destination()))
        let merged = try engine.run(.init(input: input, operation: .exportPDF(.png, .mergedTallImage), outputDirectory: destination()))
        #expect(first.outputURLs.count == 1); #expect(all.outputURLs.count == 2); #expect(merged.outputURLs.count == 1)
        #expect(try image(first.outputURLs[0]).width == 600)
        let tall = try image(merged.outputURLs[0]); #expect(tall.width == 600); #expect(tall.height == 800)
        let bytes = try rgba(tall)
        // CGImage rows are displayed top-to-bottom: page one occupies the top half.
        let upper = (380 * tall.width + 20) * 4, lower = (780 * tall.width + 20) * 4
        let firstBytes = try rgba(image(first.outputURLs[0]))
        #expect(Array(bytes[upper..<(upper + 4)]) == Array(firstBytes[upper..<(upper + 4)]))
        #expect(bytes[upper] > 230 && bytes[upper + 1] < 80)
        #expect(bytes[lower + 1] > 230 && bytes[lower] < 20)
        #expect(try Data(contentsOf: input) == original)
    }

    @Test func splitRetainsTextAndIndependentPagesWithoutSourceMutation() throws {
        let input = try pdf(); let original = try Data(contentsOf: input)
        let result = try engine.run(.init(input: input, operation: .splitPDF))
        #expect(result.outputURLs.count == 2)
        for (index, output) in result.outputURLs.enumerated() {
            let document = try #require(PDFDocument(url: output))
            #expect(document.pageCount == 1); #expect(document.string?.contains("ORBIT SECRET \(index + 1)") == true)
            #expect(document.string?.contains("ORBIT SECRET \(index == 0 ? 2 : 1)") == false)
        }
        #expect(try Data(contentsOf: input) == original)
    }

    @Test func ocrFindsActualImageAndPDFTextLocally() throws {
        let input = try pdf(pages: 1)
        let rendered = try engine.run(.init(input: input, operation: .exportPDF(.png, .firstPage)))
        for url in [input, rendered.outputURLs[0]] {
            let before = try Data(contentsOf: url)
            let result = try engine.run(.init(input: url, operation: .ocrText))
            let text = try String(contentsOf: result.outputURLs[0], encoding: .utf8)
            #expect(text.contains("ORBIT SECRET 1"))
            #expect(try Data(contentsOf: url) == before)
        }
    }

    @Test(.enabled(if: EngineEnvironment.discover().qpdfURL != nil))
    func scrubPDFRemovesInfoAndXMPPreservingContent() throws {
        let input = try metadataPDF(); let before = try Data(contentsOf: input)
        let result = try engine.run(.init(input: input, operation: .scrubMetadata))
        let output = try #require(CGPDFDocument(result.outputURLs[0] as CFURL))
        #expect(output.info == nil || CGPDFDictionaryGetCount(output.info!) == 0)
        var object: CGPDFObjectRef?
        let catalog = try #require(output.catalog)
        #expect(!CGPDFDictionaryGetObject(catalog, "Metadata", &object))
        #expect(PDFDocument(url: result.outputURLs[0])?.string?.contains("ORBIT SECRET") == true)
        #expect(!String(decoding: try Data(contentsOf: result.outputURLs[0]), as: UTF8.self).contains("PRIVATE"))
        #expect(!String(decoding: try Data(contentsOf: result.outputURLs[0]), as: UTF8.self).lowercased().contains("1234567890abcdef1234567890abcdef12"))
        #expect(try Data(contentsOf: input) == before)
    }

    @Test func scrubImageRemovesGPSAuthorAndEXIFWithoutResizing() throws {
        let input = folder.appendingPathComponent("metadata.jpg")
        let raster = try image(engine.run(.init(input: pdf(pages: 1), operation: .exportPDF(.png, .firstPage))).outputURLs[0])
        let output = try #require(CGImageDestinationCreateWithURL(input as CFURL, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(output, raster, [kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "PRIVATE"], kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 37.0, kCGImagePropertyGPSLatitudeRef: "N"], kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFArtist: "PRIVATE"]] as CFDictionary)
        #expect(CGImageDestinationFinalize(output))
        let before = try Data(contentsOf: input)
        let result = try engine.run(.init(input: input, operation: .scrubMetadata))
        let imageSource = try #require(CGImageSourceCreateWithURL(result.outputURLs[0] as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any])
        #expect(properties[kCGImagePropertyGPSDictionary as String] == nil)
        #expect(!String(describing: properties).contains("PRIVATE"))
        #expect(try image(result.outputURLs[0]).width == raster.width)
        #expect(try Data(contentsOf: input) == before)
    }

    @Test(arguments: [0, 90, 180, 270]) @MainActor
    func redactionBurnsDisplayedCoordinatesAndRemovesText(rotation: Int) throws {
        let input = try pdf(pages: 1)
        let document = try #require(PDFDocument(url: input)); document.page(at: 0)?.rotation = rotation
        #expect(document.write(to: input)); let original = try Data(contentsOf: input)
        let rect = CGRect(x: 0.1, y: 0.1, width: 0.35, height: 0.3)
        let result = try engine.run(.init(input: input, operation: .redactPDF([.init(pageIndex: 0, normalizedRect: rect)])))
        let redacted = try #require(PDFDocument(url: result.outputURLs[0]))
        #expect((redacted.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(redacted.page(at: 0)?.annotations.isEmpty == true)
        let author = redacted.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String ?? ""
        #expect(!author.contains("PRIVATE"))
        let exported = try engine.run(.init(input: result.outputURLs[0], operation: .exportPDF(.png, .firstPage)))
        let bitmap = try image(exported.outputURLs[0]); let bytes = try rgba(bitmap)
        let point = (Int(Double(bitmap.height) * 0.25) * bitmap.width + Int(Double(bitmap.width) * 0.25)) * 4
        #expect(bytes[point] < 10 && bytes[point + 1] < 10 && bytes[point + 2] < 10)
        // Sample the entire marked interior, not only one pixel that might already contain text.
        var nonBlack = 0
        for y in stride(from: Int(CGFloat(bitmap.height) * rect.minY) + 2, to: Int(CGFloat(bitmap.height) * rect.maxY) - 2, by: 3) {
            for x in stride(from: Int(CGFloat(bitmap.width) * rect.minX) + 2, to: Int(CGFloat(bitmap.width) * rect.maxX) - 2, by: 3) {
                let offset = (y * bitmap.width + x) * 4
                if bytes[offset] > 10 || bytes[offset + 1] > 10 || bytes[offset + 2] > 10 { nonBlack += 1 }
            }
        }
        #expect(nonBlack == 0)
        #expect(bitmap.width == (rotation % 180 == 0 ? 600 : 400))
        #expect(bitmap.height == (rotation % 180 == 0 ? 400 : 600))
        #expect(try Data(contentsOf: input) == original)
    }

    @Test func invalidRedactionAndCancellationPublishNothing() throws {
        let input = try pdf(); let output = try destination()
        for regions: [RedactionRegion] in [[], [.init(pageIndex: 10, normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 1))], [.init(pageIndex: 0, normalizedRect: CGRect(x: -0.1, y: 0, width: 1, height: 1))]] {
            #expect(throws: (any Error).self) { try engine.run(.init(input: input, operation: .redactPDF(regions), outputDirectory: output)) }
        }
        let token = CancellationToken(); token.cancel()
        for operation: FileOperation in [.splitPDF, .ocrText, .scrubMetadata, .exportPDF(.png, .mergedTallImage)] {
            #expect(throws: (any Error).self) { try engine.run(.init(input: input, operation: operation, outputDirectory: output), cancellation: token) }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: output.path).isEmpty)
    }

    @Test func redactionRemovesOriginalMetadataAndUnmarkedPageTextObjects() throws {
        let input = try metadataPDF()
        let result = try engine.run(.init(input: input, operation: .redactPDF([.init(pageIndex: 0, normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 1))])))
        let reference = try #require(CGPDFDocument(result.outputURLs[0] as CFURL))
        #expect(reference.info == nil)
        let bytes = try Data(contentsOf: result.outputURLs[0])
        #expect(!String(decoding: bytes, as: UTF8.self).contains("PRIVATE"))
        #expect(!String(decoding: bytes, as: UTF8.self).contains("ORBIT SECRET"))
        #expect(throws: (any Error).self) { try engine.run(.init(input: result.outputURLs[0], operation: .ocrText)) }
        let multipage = try pdf()
        let other = try engine.run(.init(input: multipage, operation: .redactPDF([.init(pageIndex: 0, normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 1))])))
        let output = try #require(PDFDocument(url: other.outputURLs[0]))
        #expect(output.pageCount == 2)
        #expect((output.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        let recognized = try engine.run(.init(input: other.outputURLs[0], operation: .ocrText))
        let text = try String(contentsOf: recognized.outputURLs[0], encoding: .utf8)
        #expect(!text.contains("ORBIT SECRET 1")); #expect(text.contains("ORBIT SECRET 2"))
    }

    @Test @MainActor func modifyingSignedAndEncryptedPDFsNeverPublishes() throws {
        let source = try pdf(), destination = try destination()
        let document = try #require(PDFDocument(url: source))
        let annotation = PDFAnnotation(bounds: CGRect(x: 10, y: 10, width: 40, height: 20), forType: .widget, withProperties: nil)
        annotation.widgetFieldType = .signature
        document.page(at: 0)?.addAnnotation(annotation)
        #expect(document.write(to: source))
        for operation: FileOperation in [.splitPDF, .scrubMetadata, .redactPDF([.init(pageIndex: 0, normalizedRect: CGRect(x: 0, y: 0, width: 0.5, height: 0.5))])] {
            #expect(throws: (any Error).self) { try engine.run(.init(input: source, operation: operation, outputDirectory: destination)) }
        }
        let encrypted = folder.appendingPathComponent("encrypted.pdf")
        #expect(document.write(to: encrypted, withOptions: [.ownerPasswordOption: "owner", .userPasswordOption: "secret"]))
        for operation: FileOperation in [.splitPDF, .scrubMetadata, .ocrText, .exportPDF(.png, .firstPage)] {
            #expect(throws: (any Error).self) { try engine.run(.init(input: encrypted, operation: operation, outputDirectory: destination)) }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty)
    }

    @Test func repeatedSplitNeverReplacesExistingResult() throws {
        let input = try pdf(), directory = try destination()
        let first = try engine.run(.init(input: input, operation: .splitPDF, outputDirectory: directory))
        let snapshot = try first.outputURLs.map { try Data(contentsOf: $0) }
        let second = try engine.run(.init(input: input, operation: .splitPDF, outputDirectory: directory))
        #expect(first.outputURLs[0].deletingLastPathComponent() != second.outputURLs[0].deletingLastPathComponent())
        #expect(try first.outputURLs.map { try Data(contentsOf: $0) } == snapshot)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 2)
    }

    @Test func cancellationAfterPDFStagingBeginsRemovesEveryPartialOutput() throws {
        let input = try pdf(pages: 200), output = try destination(), token = CancellationToken()
        let before = try Data(contentsOf: input)
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            defer { finished.signal() }
            let deadline = Date().addingTimeInterval(3)
            while Date() < deadline {
                if (try? FileManager.default.contentsOfDirectory(atPath: output.path).contains { $0.hasPrefix(".fileorbit-") }) == true {
                    token.cancel(); return
                }
                Thread.sleep(forTimeInterval: 0.001)
            }
        }
        #expect(throws: (any Error).self) { try engine.run(.init(input: input, operation: .exportPDF(.png, .allPages), outputDirectory: output), cancellation: token) }
        #expect(finished.wait(timeout: .now() + 4) == .success)
        #expect(token.isCancelled)
        #expect(try FileManager.default.contentsOfDirectory(atPath: output.path).isEmpty)
        #expect(try Data(contentsOf: input) == before)
    }

    @Test(arguments: [0, 90, 180, 270]) @MainActor
    func croppedRotatedRedactionKeepsDisplayedGeometry(rotation: Int) throws {
        let input = try pdf(pages: 1), document = try #require(PDFDocument(url: input))
        let page = try #require(document.page(at: 0))
        page.setBounds(CGRect(x: 30, y: 25, width: 200, height: 120), for: .cropBox); page.rotation = rotation
        #expect(document.write(to: input))
        let original = try engine.run(.init(input: input, operation: .exportPDF(.png, .firstPage)))
        let result = try engine.run(.init(input: input, operation: .redactPDF([.init(pageIndex: 0, normalizedRect: CGRect(x: 0.05, y: 0.05, width: 0.2, height: 0.2))])))
        let rendered = try engine.run(.init(input: result.outputURLs[0], operation: .exportPDF(.png, .firstPage)))
        let bitmap = try image(rendered.outputURLs[0]), baseline = try image(original.outputURLs[0])
        #expect(bitmap.width == baseline.width); #expect(bitmap.height == baseline.height)
        #expect(bitmap.width == (rotation % 180 == 0 ? 400 : 240))
        let pixels = try rgba(bitmap), before = try rgba(baseline)
        let marked = (bitmap.height / 10 * bitmap.width + bitmap.width / 10) * 4
        #expect(pixels[marked] < 10 && pixels[marked + 1] < 10 && pixels[marked + 2] < 10)
        var unchanged = 0, sampled = 0
        for y in stride(from: bitmap.height / 3, to: bitmap.height, by: 3) {
            for x in stride(from: 0, to: bitmap.width, by: 3) {
                let offset = (y * bitmap.width + x) * 4
                sampled += 1
                if abs(Int(pixels[offset]) - Int(before[offset])) < 5 { unchanged += 1 }
            }
        }
        #expect(Double(unchanged) / Double(sampled) > 0.97)
    }

    @Test(.enabled(if: EngineEnvironment.discover().cwebpURL != nil))
    func mergedWebPRespectsCodecDimensionLimit() throws {
        let result = try engine.run(.init(input: pdf(pages: 90), operation: .exportPDF(.webp, .mergedTallImage)))
        let bitmap = try image(result.outputURLs[0])
        #expect(bitmap.height <= 16383); #expect(bitmap.width * bitmap.height <= 32_000_000)
    }

    @Test func modificationCatalogUsesRealDependencies() {
        let input = folder.appendingPathComponent("test.pdf")
        let noDependencies = CapabilityCatalog.modificationActions(for: input, environment: EngineEnvironment()).map(\.operation)
        #expect(noDependencies.contains(.splitPDF)); #expect(noDependencies.contains(.ocrText))
        #expect(noDependencies.contains(.redactPDF([]))); #expect(!noDependencies.contains(.scrubMetadata))
        #expect(CapabilityCatalog.modificationActions(for: folder.appendingPathComponent("test.docx"), environment: EngineEnvironment()).map(\.operation) == [.compress(.balanced)])
    }

    @Test(.enabled(if: EngineEnvironment.discover().cwebpURL != nil))
    func webPUsesRealEncoderForImagesPDFAndSVG() throws {
        let input = try pdf(pages: 1)
        let png = try engine.run(.init(input: input, operation: .exportPDF(.png, .firstPage))).outputURLs[0]
        let svg = folder.appendingPathComponent("drawing.svg")
        try Data("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"80\" height=\"40\"><rect width=\"80\" height=\"40\" fill=\"red\"/></svg>".utf8).write(to: svg)
        var inputs = [input, png]
        if EngineEnvironment.discover().resvgURL != nil { inputs.append(svg) }
        for source in inputs {
            let before = try Data(contentsOf: source)
            let result = try engine.run(.init(input: source, operation: FileKind.detect(source) == .pdf ? .exportPDF(.webp, .firstPage) : .convert(.webp)))
            let bytes = try Data(contentsOf: result.outputURLs[0])
            #expect(String(data: bytes.prefix(4), encoding: .ascii) == "RIFF")
            #expect(String(data: bytes[8..<12], encoding: .ascii) == "WEBP")
            #expect(try image(result.outputURLs[0]).width == (source == svg ? 80 : 600))
            #expect(try Data(contentsOf: source) == before)
        }
        #expect(!CapabilityCatalog.actions(for: png, environment: EngineEnvironment()).contains { $0.operation == .convert(.webp) })
        #expect(CapabilityCatalog.actions(for: png, environment: EngineEnvironment.discover()).contains { $0.operation == .convert(.webp) })
    }

    /// A minimal valid PDF with Info, a ModDate, and catalog XMP. The sentinel is absent from visible text.
    func metadataPDF() throws -> URL {
        let contents = "BT /F1 24 Tf 20 100 Td (ORBIT SECRET) Tj ET"
        let xmp = "<?xpacket begin=\"\"?><x:xmpmeta xmlns:x=\"adobe:ns:meta/\">PRIVATE XMP</x:xmpmeta><?xpacket end=\"w\"?>"
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R /Metadata 6 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 200] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
            "<< /Length \(contents.utf8.count) >>\nstream\n\(contents)\nendstream",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
            "<< /Type /Metadata /Subtype /XML /Length \(xmp.utf8.count) >>\nstream\n\(xmp)\nendstream",
            "<< /Author (PRIVATE AUTHOR) /ModDate (D:20261024120000) >>"
        ]
        var text = "%PDF-1.7\n", offsets = [0]
        for (index, object) in objects.enumerated() { offsets.append(text.utf8.count); text += "\(index + 1) 0 obj\n\(object)\nendobj\n" }
        let xref = text.utf8.count
        text += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets.dropFirst() { text += String(format: "%010d 00000 n \n", offset) }
        text += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R /Info 7 0 R /ID [<1234567890ABCDEF1234567890ABCDEF12> <1234567890ABCDEF1234567890ABCDEF12>] >>\nstartxref\n\(xref)\n%%EOF\n"
        let url = folder.appendingPathComponent("private.pdf"); try Data(text.utf8).write(to: url); return url
    }
}
