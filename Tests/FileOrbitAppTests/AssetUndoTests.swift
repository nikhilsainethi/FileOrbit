import AppKit
import Testing
import FileOrbitCore
@testable import FileOrbit

@MainActor struct AssetUndoTests {
    @Test func assetInventoryNeverIncludesUserAdditions() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("icon.png")
        let context = try #require(CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 4096, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.1, green: 0.6, blue: 0.5, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
        let pixels = try #require(context.makeImage()), bytes = try #require(NSBitmapImageRep(cgImage: pixels).representation(using: .png, properties: [:]))
        try bytes.write(to: input)
        let result = try DeveloperPayloadEngine().run(input: input, operation: .appIconset)
        let inventory = try #require(result.undoURLs), directory = try #require(result.outputURLs.first)
        #expect(inventory.count == 11)
        let early = directory.appendingPathComponent("user-before-snapshot.txt"), late = directory.appendingPathComponent("user-after-snapshot.txt")
        try Data("keep early".utf8).write(to: early)
        let record = try OutputUndoRecord.capture(source: input, outputs: inventory)
        try Data("keep late".utf8).write(to: late)
        try record.undo(trash: { try FileManager.default.removeItem(at: $0) })
        #expect(try String(contentsOf: early, encoding: .utf8) == "keep early")
        #expect(try String(contentsOf: late, encoding: .utf8) == "keep late")
        #expect(try Data(contentsOf: input) == bytes)
        #expect(inventory.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        let symlink = directory.appendingPathComponent("replaced.png")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: input)
        #expect(throws: (any Error).self) { try OutputUndoRecord.snapshot(source: input, outputs: [symlink]) }
    }
}
