import Testing
import Foundation
import CoreGraphics
import ImageIO
@testable import FileOrbitCore

@Suite struct ImagePreviewTests {
    @Test func identicalAndChangedSSIM() throws {
        let a = [Double](repeating: 0.5, count: 256)
        #expect(try StructuralSimilarity.measure(a, a, width: 16, height: 16) == 1)
        #expect(try StructuralSimilarity.measure(a, [Double](repeating: 0.2, count: 256), width: 16, height: 16) < 0.8)
        #expect(throws: (any Error).self) { try StructuralSimilarity.measure(a, [], width: 16, height: 16) }
    }
    @Test func actualEncodingAndCancellation() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("fixture.png")
        let ctx = try #require(CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 0.1, green: 0.5, blue: 0.7, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
        let image = try #require(ctx.makeImage())
        try NativeConverter.encode(image, to: source, format: .png, quality: 1)
        let original = try Data(contentsOf: source)
        let preview = try await ImagePreviewActor().preview(input: source, operation: .convert(.jpg), environment: EngineEnvironment())
        #expect(preview.inputBytes == original.count)
        #expect(preview.outputBytes == preview.encodedOutput.count)
        let final = try ConversionEngine(environment: EngineEnvironment()).run(ConversionRequest(input: source, operation: .convert(.jpg)))
        #expect(try Data(contentsOf: final.outputURLs[0]) == preview.encodedOutput)
        #expect(preview.ssim > 0.98)
        #expect(preview.width == 256 && preview.height == 256)
        #expect(CGImageSourceCreateWithData(preview.outputCropPNG as CFData, nil) != nil)
        #expect(try Data(contentsOf: source) == original)
        let token = CancellationToken(); token.cancel()
        await #expect(throws: (any Error).self) { try await ImagePreviewActor().preview(input: source, operation: .convert(.jpg), environment: EngineEnvironment(), cancellation: token) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == ["fixture-converted.jpg", "fixture.png"])
    }
}
