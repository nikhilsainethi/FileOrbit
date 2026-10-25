import Testing
import ImageIO
import CoreGraphics
import CoreText
import PDFKit
import AppKit
@testable import FileOrbitCore

@Suite(.serialized)
final class NativeConversionTests {
    var temporary: URL!
    init() throws {
        temporary = FileManager.default.temporaryDirectory.appendingPathComponent("fileorbit-native-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: temporary) }

    func image(_ name: String = "example.png", width: Int = 80, height: Int = 40, orientation: Int = 1, pages: Int = 1) throws -> URL {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.1, green: 0.7, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        let url = temporary.appendingPathComponent(name)
        let type = name.hasSuffix("tiff") ? "public.tiff" : "public.png"
        let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, pages, nil)!
        for _ in 0..<pages {
            CGImageDestinationAddImage(destination, context.makeImage()!, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        }
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    func pdf(pages: Int = 2, text: Bool = true) throws -> URL {
        let url = temporary.appendingPathComponent("source.pdf")
        var box = CGRect(x: 0, y: 0, width: 200, height: 100)
        let context = CGContext(url as CFURL, mediaBox: &box, nil)!
        for index in 1...pages {
            context.beginPDFPage(nil)
            if text {
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: "FileOrbit page \(index)", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 14, nil)]))
                context.textPosition = CGPoint(x: 15, y: 45)
                CTLineDraw(line, context)
            }
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }

    func workspace(_ name: String = UUID().uuidString) throws -> URL {
        let url = temporary.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func testImageToJPEGHasCorrectDimensionsAndWhiteBackground() throws {
        let source = try image()
        let before = try Data(contentsOf: source)
        let output = try NativeConverter.convert(input: source, to: .jpg, workspace: workspace(), cancellation: CancellationToken())[0]
        let decoded = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(output as CFURL, nil)!, 0, nil)!
        #expect(decoded.width == 80); #expect(decoded.height == 40)
        let context = CGContext(data: nil, width: 80, height: 40, bitsPerComponent: 8, bytesPerRow: 320, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(decoded, in: CGRect(x: 0, y: 0, width: 80, height: 40))
        let pixel = context.data!.assumingMemoryBound(to: UInt8.self) + (20 * 80 + 70) * 4
        #expect(pixel[0] > 245); #expect(pixel[1] > 245); #expect(pixel[2] > 245)
        #expect(try Data(contentsOf: source) == before)
    }

    @Test func testImageOrientationIsApplied() throws {
        let source = try image("rotated.tiff", orientation: 6)
        let output = try NativeConverter.convert(input: source, to: .png, workspace: workspace(), cancellation: CancellationToken())[0]
        let decoded = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(output as CFURL, nil)!, 0, nil)!
        #expect(decoded.width == 40); #expect(decoded.height == 80)
    }

    @Test func testMultipageImageIsRejected() throws {
        let source = try image("multipage.tiff", pages: 2)
        #expect(throws: (any Error).self) { try NativeConverter.convert(input: source, to: .png, workspace: workspace(), cancellation: CancellationToken()) }
    }

    @Test func testPDFRenderPreservesPageCount() throws {
        let source = try pdf()
        let outputs = try NativeConverter.convertPDF(input: source, to: .png, workspace: workspace(), cancellation: CancellationToken())
        #expect(outputs.count == 2)
        for output in outputs {
            let decoded = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(output as CFURL, nil)!, 0, nil)!
            #expect(decoded.width == 400); #expect(decoded.height == 200)
        }
    }

    @Test func testPDFTextExtractsActualText() throws {
        let outputs = try NativeConverter.convertPDF(input: pdf(), to: .txt, workspace: workspace(), cancellation: CancellationToken())
        let content = try String(contentsOf: outputs[0], encoding: .utf8)
        #expect(content.contains("FileOrbit page 1")); #expect(content.contains("FileOrbit page 2"))
    }

    @Test func testPDFWithoutTextRejectsEmptyTextExport() throws {
        #expect(throws: (any Error).self) { try NativeConverter.convertPDF(input: pdf(text: false), to: .txt, workspace: workspace(), cancellation: CancellationToken()) }
    }

    @Test func testImageToPDFReopensAsOnePage() throws {
        let source = try image()
        let output = try NativeConverter.convert(input: source, to: .pdf, workspace: workspace(), cancellation: CancellationToken())[0]
        #expect(PDFDocument(url: output)?.pageCount == 1)
    }

    @Test func testMalformedImageAndCancelledRequestAreRejected() throws {
        let malformed = temporary.appendingPathComponent("broken.png")
        try Data("not an image".utf8).write(to: malformed)
        #expect(throws: (any Error).self) { try NativeConverter.convert(input: malformed, to: .jpg, workspace: workspace(), cancellation: CancellationToken()) }
        let token = CancellationToken(); token.cancel()
        #expect(throws: (any Error).self) { try NativeConverter.convert(input: image(), to: .jpg, workspace: workspace(), cancellation: token) }
    }

    @Test func testPublisherDoesNotReplaceExistingOutput() throws {
        let directory = try workspace("destination")
        let source = directory.appendingPathComponent("résumé '$(oops).png")
        try Data("original".utf8).write(to: source)
        let existing = directory.appendingPathComponent("résumé '$(oops)-converted.jpg")
        try Data("existing".utf8).write(to: existing)
        let staged = try workspace().appendingPathComponent("image.jpg")
        try Data("new".utf8).write(to: staged)
        let result = try OutputPublisher.publish(files: [staged], source: source, directory: directory, compressed: false)
        #expect(result[0].lastPathComponent == "résumé '$(oops)-converted 2.jpg")
        #expect(try String(contentsOf: source, encoding: .utf8) == "original")
        #expect(try String(contentsOf: existing, encoding: .utf8) == "existing")
        #expect(try String(contentsOf: result[0], encoding: .utf8) == "new")
    }

    @Test func testPublisherPlacesMultiplePagesInDistinctFolder() throws {
        let directory = try workspace("destination")
        let staging = try workspace()
        let files = (1...2).map { staging.appendingPathComponent("page-\($0).png") }
        for file in files { try Data("page".utf8).write(to: file) }
        let source = directory.appendingPathComponent("slides.pdf")
        let result = try OutputPublisher.publish(files: files, source: source, directory: directory, compressed: false)
        #expect(result.count == 2)
        #expect(result[0].deletingLastPathComponent() == result[1].deletingLastPathComponent())
        #expect(result[0].deletingLastPathComponent().lastPathComponent == "slides-converted")
    }

    @Test func testEnginePublishesValidatedImageAndCleansWorkspace() throws {
        let source = try image()
        let before = try Data(contentsOf: source)
        let directory = try workspace("final")
        let result = try ConversionEngine(environment: EngineEnvironment()).run(.init(input: source, operation: .convert(.jpg), outputDirectory: directory))
        #expect(result.outputURLs.count == 1)
        #expect(result.inputBytes == before.count)
        #expect(result.outputBytes > 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 1)
        #expect(try Data(contentsOf: source) == before)
    }

    @Test func testEngineSmallCompressionReducesSizeAndDimensions() throws {
        let source = try image("large.png", width: 3200, height: 1600)
        let before = try Data(contentsOf: source)
        let result = try ConversionEngine(environment: EngineEnvironment()).run(.init(input: source, operation: .compress(.small)))
        #expect(result.outputBytes < result.inputBytes)
        let decoded = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(result.outputURLs[0] as CFURL, nil)!, 0, nil)!
        #expect(decoded.width == 1600); #expect(decoded.height == 800)
        #expect(try Data(contentsOf: source) == before)
    }

    @Test func testEngineRejectsMissingFilesDirectoriesAndUnknownFormats() throws {
        let engine = ConversionEngine(environment: EngineEnvironment())
        for url in [temporary.appendingPathComponent("missing.jpg"), temporary!, temporary.appendingPathComponent("program.exe")] {
            #expect(throws: (any Error).self) { try engine.run(.init(input: url, operation: .convert(.png))) }
        }
    }

    @Test func testEngineNeverPublishesBiggerCompression() throws {
        let source = try image()
        let first = try NativeConverter.compress(input: source, preset: .gentle, workspace: workspace(), cancellation: CancellationToken())[0]
        let directory = try workspace("compressed-final")
        #expect(throws: (any Error).self) {
            try ConversionEngine(environment: EngineEnvironment()).run(.init(input: first, operation: .compress(.gentle), outputDirectory: directory))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test func testEngineCancelledRequestDoesNotPublish() throws {
        let source = try image()
        let directory = try workspace("cancelled-final")
        let token = CancellationToken(); token.cancel()
        #expect(throws: (any Error).self) {
            try ConversionEngine(environment: EngineEnvironment()).run(.init(input: source, operation: .convert(.jpg), outputDirectory: directory), cancellation: token)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test(.enabled(if: EngineEnvironment.discover().qpdfURL != nil, "Requires installed qpdf")) func testPDFCompressionWithInstalledQPDFPreservesTextAndPages() throws {
        let environment = EngineEnvironment.discover()
        let original = try pdf(pages: 3)
        let source = temporary.appendingPathComponent("uncompressed.pdf")
        _ = try LocalProcess.run(executable: environment.qpdfURL!, arguments: ["--stream-data=uncompress", "--object-streams=disable", original.path, source.path], cancellation: CancellationToken())
        let result = try ConversionEngine(environment: environment).run(.init(input: source, operation: .compress(.gentle)))
        #expect(result.outputBytes < result.inputBytes)
        #expect(PDFDocument(url: result.outputURLs[0])?.pageCount == 3)
        #expect(PDFDocument(url: result.outputURLs[0])?.string?.contains("FileOrbit page 3") == true)
    }

    @Test(.enabled(if: EngineEnvironment.discover().resvgURL != nil, "Requires installed resvg")) func testStaticSVGWithInstalledResvgConvertsAndRejectsExternalReferences() throws {
        let environment = EngineEnvironment.discover()
        let source = temporary.appendingPathComponent("art.svg")
        try "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"80\" height=\"40\"><rect width=\"80\" height=\"40\" fill=\"red\"/></svg>".write(to: source, atomically: true, encoding: .utf8)
        let engine = ConversionEngine(environment: environment)
        let result = try engine.run(.init(input: source, operation: .convert(.png)))
        #expect(CGImageSourceCreateWithURL(result.outputURLs[0] as CFURL, nil) != nil)
        try "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"80\" height=\"40\"><image href=\"file:///etc/passwd\"/></svg>".write(to: source, atomically: true, encoding: .utf8)
        #expect(throws: (any Error).self) { try engine.run(.init(input: source, operation: .convert(.png))) }
    }

    @Test(.enabled(if: EngineEnvironment.discover().resvgURL != nil, "Requires installed resvg")) func testSVGRejectsXMLDecodedStylesheetReferences() throws {
        let source = temporary.appendingPathComponent("linked.svg")
        let snippets = [
            "<rect width=\"80\" height=\"40\" style=\"fill:u&#114;l(file:///outside.png)\"/>",
            "<style>.a {fill:u&#114;l(file:///outside.png)}</style><rect class=\"a\" width=\"80\" height=\"40\"/>"
        ]
        for snippet in snippets {
            try "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"80\" height=\"40\">\(snippet)</svg>".write(to: source, atomically: true, encoding: .utf8)
            #expect(throws: (any Error).self) {
                try ConversionEngine(environment: .discover()).run(.init(input: source, operation: .convert(.png)))
            }
        }
    }

    @Test(arguments: [OutputFormat.png, .jpg, .heic, .tiff]) func testNativeOutputCodecsReopen(format: OutputFormat) throws {
        let source = try image()
        let output = try NativeConverter.convert(input: source, to: format, workspace: workspace(), cancellation: CancellationToken())[0]
        let decoded = try #require(CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(output as CFURL, nil)!, 0, nil))
        #expect(decoded.width == 80); #expect(decoded.height == 40)
        if format != .jpg {
            let context = CGContext(data: nil, width: 80, height: 40, bitsPerComponent: 8, bytesPerRow: 320, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(decoded, in: CGRect(x: 0, y: 0, width: 80, height: 40))
            let pixel = context.data!.assumingMemoryBound(to: UInt8.self) + (20 * 80 + 70) * 4
            #expect(pixel[3] < 10, "Transparent pixels must remain transparent in PNG, HEIC and TIFF.")
        }
    }

    @Test(arguments: [0, 90, 180, 270]) @MainActor func testPDFRenderingIncludesVisibleAnnotations(rotation: Int) async throws {
        let source = try pdf(pages: 1, text: false)
        let document = PDFDocument(url: source)!
        let page = document.page(at: 0)!
        let annotation = PDFAnnotation(bounds: CGRect(x: 20, y: 20, width: 30, height: 30), forType: .square, withProperties: nil)
        annotation.color = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        annotation.interiorColor = annotation.color
        page.addAnnotation(annotation)
        page.rotation = rotation
        #expect(document.write(to: source))
        let staging = try workspace()
        let output = try await Task.detached {
            try NativeConverter.convertPDF(input: source, to: .png, workspace: staging, cancellation: CancellationToken())[0]
        }.value
        let decoded = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(output as CFURL, nil)!, 0, nil)!
        #expect(decoded.width == (rotation % 180 == 0 ? 400 : 200))
        #expect(decoded.height == (rotation % 180 == 0 ? 200 : 400))
        let context = CGContext(data: nil, width: decoded.width, height: decoded.height, bitsPerComponent: 8, bytesPerRow: decoded.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(decoded, in: CGRect(x: 0, y: 0, width: decoded.width, height: decoded.height))
        let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
        let redPixels = (0..<(decoded.width * decoded.height)).filter { pixels[$0 * 4] > 200 && pixels[$0 * 4 + 1] < 50 && pixels[$0 * 4 + 2] < 50 }.count
        #expect(redPixels > 2500, "The visible annotation must remain in the exported image at every rotation.")
    }

    @Test(.enabled(if: EngineEnvironment.discover().qpdfURL != nil, "Requires installed qpdf")) func testEncryptedPDFIsRejectedWithoutOutput() throws {
        let environment = EngineEnvironment.discover()
        let original = try pdf(pages: 1)
        let encrypted = temporary.appendingPathComponent("encrypted.pdf")
        _ = try LocalProcess.run(executable: environment.qpdfURL!, arguments: ["--encrypt", "", "fixture-owner", "256", "--", original.path, encrypted.path], cancellation: CancellationToken())
        #expect(PDFDocument(url: encrypted)?.isEncrypted == true)
        let directory = try workspace("encrypted-final")
        #expect(throws: (any Error).self) { try ConversionEngine(environment: environment).run(.init(input: encrypted, operation: .compress(.gentle), outputDirectory: directory)) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test(.enabled(if: EngineEnvironment.discover().qpdfURL != nil, "Requires installed qpdf")) @MainActor func testPDFSignatureFieldIsRejectedWithoutOutput() throws {
        let source = try pdf(pages: 1)
        let document = PDFDocument(url: source)!
        let widget = PDFAnnotation(bounds: CGRect(x: 10, y: 10, width: 40, height: 20), forType: .widget, withProperties: nil)
        widget.widgetFieldType = .signature
        widget.fieldName = "Signature"
        document.page(at: 0)!.addAnnotation(widget)
        #expect(document.write(to: source))
        let directory = try workspace("signed-final")
        do {
            _ = try ConversionEngine(environment: .discover()).run(.init(input: source, operation: .compress(.gentle), outputDirectory: directory))
            Issue.record("Signature-bearing PDF unexpectedly compressed")
        } catch {
            #expect(error.localizedDescription.contains("signed"))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
}
