import Testing
import Foundation
@testable import FileOrbit

@MainActor struct NotchStashTests {
    @Test func bookmarksSurviveReloadAndClearPreservesOriginal() throws {
        let suite = "NotchStashTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("notch-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("source.txt")
        try Data("Original".utf8).write(to: file)
        let stash = NotchStashModel(defaults: defaults, managedDirectory: folder.appendingPathComponent("owned"))
        stash.add([file, file])
        #expect(stash.items.count == 1)
        let reloaded = NotchStashModel(defaults: defaults, managedDirectory: folder.appendingPathComponent("owned"))
        #expect(reloaded.items.count == 1)
        #expect(reloaded.items.first?.url?.standardizedFileURL == file.standardizedFileURL)
        reloaded.clear()
        #expect(try String(contentsOf: file, encoding: .utf8) == "Original")
        #expect(NotchStashModel(defaults: defaults).items.isEmpty)
    }

    @Test func missingSourceIsRetainedAsUnavailableReference() throws {
        let suite = "NotchStashMissing.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID()).txt")
        try Data("temporary".utf8).write(to: file)
        let stash = NotchStashModel(defaults: defaults)
        stash.add([file])
        try FileManager.default.removeItem(at: file)
        let reloaded = NotchStashModel(defaults: defaults)
        #expect(reloaded.items.count == 1)
        #expect(reloaded.items.first?.isAvailable == false)
    }

    @Test func optInDefaultsRemainDisabled() {
        let suite = "SpatialPreferences.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = SpatialPreferences(defaults: defaults)
        #expect(!preferences.notchEnabled && !preferences.clipboardEnabled && !preferences.screenshotEnabled)
    }
}
