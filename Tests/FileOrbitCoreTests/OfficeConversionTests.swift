import Testing
import Foundation
import PDFKit
import ImageIO
import UniformTypeIdentifiers
@testable import FileOrbitCore

@Suite final class OfficeConversionTests {
    private var root: URL!
    init() throws { root = FileManager.default.temporaryDirectory.appendingPathComponent("FileOrbit-office-tests-\(UUID().uuidString)"); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
    deinit { try? FileManager.default.removeItem(at: root) }
    private func folder(_ name: String) throws -> URL { let url = root.appendingPathComponent(name); try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url }
    private func libreOffice() throws -> URL {
        let candidates = ["/Applications/LibreOffice.app/Contents/MacOS/soffice", ProcessInfo.processInfo.environment["FILEORBIT_SOFFICE"] ?? ""]
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { throw ConversionError.missingDependency("LibreOffice is not installed") }
        return URL(fileURLWithPath: path)
    }
    @Test func testTextToPDFAndDocxHaveActualContent() throws {
        let input = root.appendingPathComponent("notes with spaces — résumé.txt")
        try "FileOrbit offline conversion\nSecond paragraph with Unicode: café.".write(to: input, atomically: true, encoding: .utf8)
        let env = EngineEnvironment(libreOfficeURL: try libreOffice())
        let pdf = try OfficeConverter.convert(input: input, to: .pdf, workspace: folder("pdf"), environment: env, cancellation: CancellationToken())
        #expect(pdf.count == 1)
        let document = try #require(PDFDocument(url: pdf[0]))
        #expect(document.pageCount == 1)
        #expect((document.string ?? "").contains("FileOrbit offline conversion"))
        let docx = try OfficeConverter.convert(input: input, to: .docx, workspace: folder("docx"), environment: env, cancellation: CancellationToken())
        let text = try OfficeConverter.convert(input: docx[0], to: .txt, workspace: folder("text"), environment: env, cancellation: CancellationToken())
        #expect(try String(contentsOf: text[0], encoding: .utf8).contains("FileOrbit offline conversion"))
    }
    @Test func testMissingOfficeDependencyIsActionable() throws {
        let input = root.appendingPathComponent("test.txt"); try "hello".write(to: input, atomically: true, encoding: .utf8)
        #expect(throws: (any Error).self) { try OfficeConverter.convert(input: input, to: .pdf, workspace: folder("out"), environment: EngineEnvironment(), cancellation: CancellationToken()) }
    }
    @Test func testCompressDocxPreservesXMLAndShrinksImage() throws {
        let package = try makeDocxPackage()
        let input = root.appendingPathComponent("image-heavy.docx")
        _ = try LocalProcess.run(executable: URL(fileURLWithPath: "/usr/bin/zip"), arguments: ["-q", "-r", input.path, "."], cancellation: CancellationToken(), directory: package)
        let beforeXML = try Data(contentsOf: package.appendingPathComponent("word/document.xml"))
        let beforeImage = try Data(contentsOf: package.appendingPathComponent("word/media/image1.jpg"))
        let output = try DocxCompressor.compress(input: input, preset: .small, workspace: folder("out"), cancellation: CancellationToken())
        let extracted = try folder("verify")
        _ = try LocalProcess.run(executable: URL(fileURLWithPath: "/usr/bin/ditto"), arguments: ["-x", "-k", output[0].path, extracted.path], cancellation: CancellationToken())
        #expect(try Data(contentsOf: extracted.appendingPathComponent("word/document.xml")) == beforeXML)
        let compressedImage = try Data(contentsOf: extracted.appendingPathComponent("word/media/image1.jpg"))
        #expect(compressedImage.count < beforeImage.count)
        #expect(CGImageSourceCreateWithData(compressedImage as CFData, nil) != nil)
    }
    @Test func testRejectsSignedDocx() throws {
        let package = try makeDocxPackage()
        try FileManager.default.createDirectory(at: package.appendingPathComponent("_xmlsignatures"), withIntermediateDirectories: true)
        try "signed".write(to: package.appendingPathComponent("_xmlsignatures/sig1.xml"), atomically: true, encoding: .utf8)
        let input = root.appendingPathComponent("signed.docx")
        _ = try LocalProcess.run(executable: URL(fileURLWithPath: "/usr/bin/zip"), arguments: ["-q", "-r", input.path, "."], cancellation: CancellationToken(), directory: package)
        #expect(throws: (any Error).self) { try DocxCompressor.compress(input: input, preset: .balanced, workspace: folder("out"), cancellation: CancellationToken()) }
    }
    @Test func testRejectsSymlinkArchive() throws {
        let package = try makeDocxPackage()
        try FileManager.default.createSymbolicLink(atPath: package.appendingPathComponent("word/media/link").path, withDestinationPath: "/etc/passwd")
        let input = root.appendingPathComponent("symlink.docx")
        _ = try LocalProcess.run(executable: URL(fileURLWithPath: "/usr/bin/zip"), arguments: ["-q", "-y", "-r", input.path, "."], cancellation: CancellationToken(), directory: package)
        #expect(throws: (any Error).self) { try DocxCompressor.compress(input: input, preset: .balanced, workspace: folder("out"), cancellation: CancellationToken()) }
    }
    @Test func testRejectsArchiveTraversalBeforeExtraction() throws {
        let package = try makeDocxPackage()
        try "outside".write(to: package.appendingPathComponent("safe.doc"), atomically: true, encoding: .utf8)
        let input = root.appendingPathComponent("traversal.docx")
        _ = try LocalProcess.run(executable: URL(fileURLWithPath: "/usr/bin/zip"), arguments: ["-q", "-r", input.path, "."], cancellation: CancellationToken(), directory: package)
        var bytes = try Data(contentsOf: input)
        let source = Data("safe.doc".utf8), unsafe = Data("../x.doc".utf8)
        while let range = bytes.range(of: source) { bytes.replaceSubrange(range, with: unsafe) }
        try bytes.write(to: input)
        #expect(throws: (any Error).self) { try DocxCompressor.compress(input: input, preset: .balanced, workspace: folder("out"), cancellation: CancellationToken()) }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("x.doc").path))
    }
    @Test func testExternalImageRelationshipIsRejectedBeforeOfficeLaunch() throws {
        let package = try makeDocxPackage()
        let relationshipFolder = package.appendingPathComponent("word/_rels")
        try FileManager.default.createDirectory(at: relationshipFolder, withIntermediateDirectories: true)
        try "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rIdExternal\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"https://example.invalid/remote.png\" TargetMode=\"External\"/></Relationships>".write(to: relationshipFolder.appendingPathComponent("document.xml.rels"), atomically: true, encoding: .utf8)
        let input = root.appendingPathComponent("external.docx")
        _ = try LocalProcess.run(executable: URL(fileURLWithPath: "/usr/bin/zip"), arguments: ["-q", "-r", input.path, "."], cancellation: CancellationToken(), directory: package)
        do {
            _ = try OfficeConverter.convert(input: input, to: .pdf, workspace: folder("out"), environment: EngineEnvironment(libreOfficeURL: URL(fileURLWithPath: "/usr/bin/true")), cancellation: CancellationToken())
            Issue.record("Expected external resource rejection")
        } catch { #expect(error.localizedDescription.contains("external resource")) }
    }
    @Test func testPresentationExportsTwoActualSlides() throws {
        let package = try folder("presentation-package")
        let files: [String: String] = [
            "[Content_Types].xml": "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/ppt/presentation.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml\"/><Override PartName=\"/ppt/slides/slide1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slide+xml\"/><Override PartName=\"/ppt/slides/slide2.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slide+xml\"/></Types>",
            "_rels/.rels": "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"ppt/presentation.xml\"/></Relationships>",
            "ppt/presentation.xml": "<p:presentation xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\"><p:sldIdLst><p:sldId id=\"256\" r:id=\"rId1\"/><p:sldId id=\"257\" r:id=\"rId2\"/></p:sldIdLst><p:sldSz cx=\"9144000\" cy=\"5143500\"/><p:notesSz cx=\"6858000\" cy=\"9144000\"/></p:presentation>",
            "ppt/_rels/presentation.xml.rels": "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide\" Target=\"slides/slide1.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide\" Target=\"slides/slide2.xml\"/></Relationships>"
        ]
        for (path, content) in files { let url = package.appendingPathComponent(path); try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true); try content.write(to: url, atomically: true, encoding: .utf8) }
        for index in 1...2 {
            let slide = "<p:sld xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\"><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/><p:sp><p:nvSpPr><p:cNvPr id=\"2\" name=\"Title\"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"914400\" y=\"914400\"/><a:ext cx=\"7315200\" cy=\"1828800\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr><p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:rPr lang=\"en-US\" sz=\"2800\"/><a:t>FileOrbit slide \(index)</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld></p:sld>"
            let url = package.appendingPathComponent("ppt/slides/slide\(index).xml"); try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true); try slide.write(to: url, atomically: true, encoding: .utf8)
        }
        let input = root.appendingPathComponent("slides.pptx")
        _ = try LocalProcess.run(executable: URL(fileURLWithPath: "/usr/bin/zip"), arguments: ["-q", "-r", input.path, "."], cancellation: CancellationToken(), directory: package)
        let env = EngineEnvironment(libreOfficeURL: try libreOffice())
        let pdf = try OfficeConverter.convert(input: input, to: .pdf, workspace: folder("pdf"), environment: env, cancellation: CancellationToken())
        let document = try #require(PDFDocument(url: pdf[0]))
        #expect(document.pageCount == 2)
        #expect((document.string ?? "").contains("FileOrbit slide 1"))
        let images = try OfficeConverter.convert(input: input, to: .png, workspace: folder("png"), environment: env, cancellation: CancellationToken())
        #expect(images.count == 2)
        for url in images { #expect(CGImageSourceCreateWithURL(url as CFURL, nil) != nil) }
    }
    private func makeDocxPackage() throws -> URL {
        let package = try folder("package")
        try FileManager.default.createDirectory(at: package.appendingPathComponent("word/media"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: package.appendingPathComponent("_rels"), withIntermediateDirectories: true)
        try "<?xml version=\"1.0\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Default Extension=\"jpg\" ContentType=\"image/jpeg\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>".write(to: package.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)
        try "<?xml version=\"1.0\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>".write(to: package.appendingPathComponent("_rels/.rels"), atomically: true, encoding: .utf8)
        try "<?xml version=\"1.0\"?><w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body><w:p><w:r><w:t>Document content must stay byte-identical.</w:t></w:r></w:p></w:body></w:document>".write(to: package.appendingPathComponent("word/document.xml"), atomically: true, encoding: .utf8)
        let width = 2400, height = 1600
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) { pixels[i * 4] = UInt8((i * 13) % 256); pixels[i * 4 + 1] = UInt8((i * 31) % 256); pixels[i * 4 + 2] = UInt8((i * 7) % 256); pixels[i * 4 + 3] = 255 }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
        let destination = CGImageDestinationCreateWithURL(package.appendingPathComponent("word/media/image1.jpg") as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return package
    }
}
