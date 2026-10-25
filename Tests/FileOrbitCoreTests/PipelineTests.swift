import Foundation
import Testing
import CoreGraphics
@testable import FileOrbitCore
@Suite struct PipelineTests {
    @Test func onlyFinalOutputPublishedAndOriginalRetained() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("sample.jpg")
        let ctx = try #require(CGContext(data: nil, width: 128, height: 128, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.setFillColor(CGColor(gray: 0.4, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
        try NativeConverter.encode(try #require(ctx.makeImage()), to: input, format: .jpg, quality: 0.9)
        let original = try Data(contentsOf: input)
        let result = try PipelineExecutor(environment: EngineEnvironment()).run(input: input, pipeline: .png)
        #expect(result.outputURLs.count == 1 && result.outputURLs[0].pathExtension == "png")
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 2)
        #expect(try Data(contentsOf: input) == original)
        let token = CancellationToken(); token.cancel()
        #expect(throws: (any Error).self) { try PipelineExecutor(environment: EngineEnvironment()).run(input: input, pipeline: .png, cancellation: token) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 2)
    }
}
