import Testing
import Foundation
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import FileOrbit

@MainActor struct ClipboardSurfaceTests {
    private func png() throws -> Data {
        let context = try #require(CGContext(data: nil, width: 24, height: 20, bitsPerComponent: 8, bytesPerRow: 96,
                                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.7, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 24, height: 20))
        let image = try #require(context.makeImage()), data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test func delayedClipboardCommitCannotClobberNewContent() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let data = try png()
        pasteboard.setData(data, forType: .png)
        let snapshot = ClipboardSnapshot(data: data, typeIdentifier: UTType.png.identifier, changeCount: pasteboard.changeCount)
        let sentinel = PasteboardSentinel(pasteboard: pasteboard)
        pasteboard.clearContents(); pasteboard.setString("New clipboard content", forType: .string)
        #expect(throws: (any Error).self) { try sentinel.commit(data: data, typeIdentifier: UTType.png.identifier, for: snapshot) }
        #expect(pasteboard.string(forType: .string) == "New clipboard content")
    }

    @Test func successfulClipboardCommitCarriesGeneratedMarkerAndRealImage() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let data = try png()
        pasteboard.setData(data, forType: .png)
        let snapshot = ClipboardSnapshot(data: data, typeIdentifier: UTType.png.identifier, changeCount: pasteboard.changeCount)
        let sentinel = PasteboardSentinel(pasteboard: pasteboard)
        try sentinel.commit(data: data, typeIdentifier: UTType.png.identifier, for: snapshot)
        #expect(pasteboard.data(forType: .png) == data)
        #expect(pasteboard.string(forType: NSPasteboard.PasteboardType(ClipboardSnapshot.generatedMarker)) == "FileOrbit")
        #expect(!sentinel.isCurrent(snapshot))
    }

    @Test func orbSupersededCompletionDoesNotFinishCurrentOperation() throws {
        let model = ClipboardOrbModel(), data = try png()
        let first = ClipboardSnapshot(data: data, typeIdentifier: UTType.png.identifier, changeCount: 1)
        let second = ClipboardSnapshot(data: data, typeIdentifier: UTType.png.identifier, changeCount: 2)
        model.present(first, at: 0)
        model.present(second, at: 1)
        model.onAction = { _, _ in }
        model.activate(.sanitize)
        #expect(model.processing)
        model.finish(message: "Old finished", snapshotID: first.id)
        #expect(model.processing)
        model.finish(message: "Reviewed", snapshotID: second.id)
        #expect(!model.processing)
        #expect(model.message == "Reviewed")
    }

    @Test func clipboardPinRemovesOnlyManagedCopy() throws {
        let suite = "ClipboardPin.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("clipboard-pin-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = NotchStashModel(defaults: defaults, managedDirectory: folder)
        let snapshot = ClipboardSnapshot(data: try png(), typeIdentifier: UTType.png.identifier, changeCount: 0)
        let url = try model.pin(snapshot)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(model.items.count == 1)
        #expect(model.items.first?.isManagedCopy == true)
        model.clear()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
    @Test func commitRejectsMislabeledEncodingWithoutClearingClipboard() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let data = try png()
        pasteboard.setString("Keep this", forType: .string)
        let snapshot = ClipboardSnapshot(data: data, typeIdentifier: UTType.png.identifier, changeCount: pasteboard.changeCount)
        let sentinel = PasteboardSentinel(pasteboard: pasteboard)
        #expect(throws: (any Error).self) { try sentinel.commit(data: data, typeIdentifier: UTType.webP.identifier, for: snapshot) }
        #expect(pasteboard.string(forType: .string) == "Keep this")
    }

}
