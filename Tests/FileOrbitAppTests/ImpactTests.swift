import Foundation
import Testing
import FileOrbitCore
@testable import FileOrbit

@MainActor @Suite struct ImpactTests {
    @Test func accountingIsMeasuredDeduplicatedAndReversible() throws {
        let name = "FileOrbit.tests.impact.\(UUID().uuidString)", defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ImpactStore(defaults: defaults), id = UUID()
        store.record(id: id, category: .compression, inputBytes: 1000, outputBytes: 600)
        store.record(id: id, category: .compression, inputBytes: 1000, outputBytes: 600)
        #expect(store.totalOperations == 1 && store.avoidedBytes == 400)
        #expect(store.estimatedSeconds == 20)
        #expect(ImpactStore(defaults: defaults).avoidedBytes == 400)
        store.record(id: UUID(), category: .conversion, inputBytes: 100, outputBytes: 300)
        #expect(store.avoidedBytes == 400)
        store.undo(id: id); store.undo(id: id)
        #expect(store.totalOperations == 1 && store.avoidedBytes == 0)
        store.record(id: UUID(), category: .conversion, inputBytes: -1, outputBytes: 3)
        #expect(store.totalOperations == 1)
        #expect(String(data: try #require(defaults.data(forKey: "FileOrbit.impact.v1")), encoding: .utf8)?.contains("inputPath") == false)
    }
    @Test func corruptCountersDoNotCrashAccounting() throws {
        let name = "FileOrbit.tests.impact.corrupt.\(UUID().uuidString)", defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data(#"{"operations":{"conversion":1},"avoided":9223372036854775807,"daily":{},"recent":[]}"#.utf8), forKey: "FileOrbit.impact.v1")
        let store = ImpactStore(defaults: defaults)
        #expect(store.avoidedBytes == 0)
        store.record(id: UUID(), category: .conversion, inputBytes: 10, outputBytes: 1)
        #expect(store.avoidedBytes == 9)
    }
    @Test func completedUndoReversesOldJobEvenWhenNewJobStarts() async throws {
        let name = "FileOrbit.tests.impact.undo.\(UUID().uuidString)", defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("source.txt"), output = directory.appendingPathComponent("output.txt")
        try Data("original".utf8).write(to: input); try Data("copy".utf8).write(to: output)
        let store = ImpactStore(defaults: defaults), hud = JobHUDModel(impactStore: store), id = UUID()
        store.record(id: id, category: .conversion, inputBytes: 8, outputBytes: 4)
        hud.complete(input: input, result: ConversionResult(outputURLs: [output], inputBytes: 8, outputBytes: 4))
        hud.impactID = id
        for _ in 0..<200 where !hud.canUndo { try await Task.sleep(for: .milliseconds(5)) }
        #expect(hud.canUndo)
        hud.undoExecutor = { record in Thread.sleep(forTimeInterval: 0.08); try record.undo(trash: { try FileManager.default.removeItem(at: $0) }) }
        hud.undo(); hud.setRunning(input: input)
        for _ in 0..<200 where store.totalOperations > 0 { try await Task.sleep(for: .milliseconds(5)) }
        #expect(store.totalOperations == 0 && store.avoidedBytes == 0)
        #expect(hud.phase == .running)
        #expect(!FileManager.default.fileExists(atPath: output.path))
        #expect(FileManager.default.fileExists(atPath: input.path))
    }

}
