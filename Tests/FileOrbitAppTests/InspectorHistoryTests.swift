import Foundation
import Testing
@testable import FileOrbit
import FileOrbitCore

@Suite("Inspector and history")
struct InspectorHistoryTests {
    @Test func metadataReportsRealFileSize() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("metadata-\(UUID()).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(repeating: 65, count: 3_072).write(to: url)
        let metadata = try FileMetadataSnapshot.read(url)
        #expect(metadata.bytes == 3_072)
        #expect(metadata.pageCount == nil)
        #expect(!metadata.sizeText.isEmpty)
    }
    @Test @MainActor func clearingInspectorDiscardsPendingMetadata() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("metadata-\(UUID()).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("Text".utf8).write(to: url)
        let inspector = FileInspector()
        inspector.load(url)
        inspector.load(nil)
        try await Task.sleep(for: .milliseconds(100))
        #expect(inspector.thumbnail == nil)
        #expect(inspector.sizeText.isEmpty)
        #expect(inspector.metadataText.isEmpty)
    }
    @Test @MainActor func historyIsSessionOnlyUnlessOptedInAndClearsPersistence() {
        let name = "HistoryTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let history = JobHistory(defaults: defaults)
        history.record(input: URL(fileURLWithPath: "/tmp/input.png"), result: ConversionResult(outputURLs: [URL(fileURLWithPath: "/tmp/output.jpg")], inputBytes: 100, outputBytes: 80))
        #expect(history.entries.count == 1)
        #expect(JobHistory(defaults: defaults).entries.isEmpty)
        history.setRememberHistory(true)
        #expect(JobHistory(defaults: defaults).entries.count == 1)
        history.setRememberHistory(false)
        #expect(JobHistory(defaults: defaults).entries.isEmpty)
        #expect(history.entries.count == 1)
        history.clear()
        #expect(history.entries.isEmpty)
    }
}
