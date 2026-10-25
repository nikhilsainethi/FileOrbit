import Testing
import Foundation
import ImageIO
import PDFKit
@testable import FileOrbit

@Suite struct OnboardingSandboxTests {
    @Test func generatedSamplesAreRealFilesAndOutputsStayInSeparateSandboxFolder() throws {
        let assets = try OnboardingSandboxAssets.create()
        defer { try? FileManager.default.removeItem(at: assets.directory) }
        #expect(assets.portrait.lastPathComponent == "Studio_Portrait.png")
        #expect(assets.deck.lastPathComponent == "Sample_Deck.pdf")
        let source = try #require(CGImageSourceCreateWithURL(assets.portrait as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 640 && image.height == 640)
        let pdf = try #require(PDFDocument(url: assets.deck))
        #expect(pdf.pageCount == 1 && pdf.string?.contains("FileOrbit") == true)
        #expect(assets.outputDirectory.deletingLastPathComponent() == assets.directory)
        #expect(try FileManager.default.contentsOfDirectory(atPath: assets.outputDirectory.path).isEmpty)
        #expect((try FileManager.default.attributesOfItem(atPath: assets.directory.path)[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    }
}
