import Foundation
import CoreGraphics
import Testing
@testable import FileOrbit
import FileOrbitCore

@Suite("Auxiliary models")
struct AuxiliaryModelTests {
    @Test @MainActor func radialOrderKeepsNewActionsAndRemovesUnavailableOnes() {
        let name = "FileOrbitTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = StudioPreferences(defaults: defaults)
        preferences.setOrder(["jpg", "png", "retired", "jpg"], mode: "convert")
        #expect(preferences.orderedIDs(["png", "pdf", "jpg"], mode: "convert") == ["jpg", "png", "pdf"])
        preferences.move(id: "pdf", before: "jpg", availableIDs: ["png", "pdf", "jpg"], mode: "convert")
        #expect(preferences.orderedIDs(["png", "pdf", "jpg"], mode: "convert") == ["pdf", "jpg", "png"])
        #expect(preferences.orderedIDs(["png", "pdf"], mode: "modify") == ["png", "pdf"])
    }

    @Test @MainActor func shelfDeduplicatesAndUsesOnlyCommonFormats() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("one.txt")
        let second = directory.appendingPathComponent("two.docx")
        try Data("Text".utf8).write(to: first)
        try Data("Document".utf8).write(to: second)
        let shelf = GlassShelfModel(environment: EngineEnvironment(libreOfficeURL: URL(fileURLWithPath: "/mock/soffice")))
        shelf.add([first, first, second])
        #expect(shelf.items.count == 2)
        #expect(shelf.availableFormats == [.pdf])
        #expect(!shelf.canCompressAll)
        shelf.mode = .compress
        #expect(!shelf.canRun)
    }

    @Test func undoRejectsChangedOutputAndSourceAlias() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.txt")
        let output = directory.appendingPathComponent("output.txt")
        try Data("Source".utf8).write(to: source)
        try Data("Result".utf8).write(to: output)
        let undo = try OutputUndoRecord.capture(source: source, outputs: [output])
        #expect(try undo.validate())
        try Data("Edited".utf8).write(to: output)
        #expect(throws: (any Error).self) { try undo.validate() }
        #expect(throws: (any Error).self) { try OutputUndoRecord.capture(source: source, outputs: [source]) }
        let alias = directory.appendingPathComponent("alias.txt")
        try FileManager.default.linkItem(at: source, to: alias)
        #expect(throws: (any Error).self) { try OutputUndoRecord.capture(source: source, outputs: [alias]) }
        #expect(try String(contentsOf: source, encoding: .utf8) == "Source")
    }

    @Test func undoMovesOnlyCapturedFilesAndLeavesNewFolderContents() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.pdf")
        let folder = directory.appendingPathComponent("pages")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let output = folder.appendingPathComponent("page1.png")
        let userFile = folder.appendingPathComponent("my-notes.txt")
        try Data("source".utf8).write(to: source)
        try Data("page".utf8).write(to: output)
        let undo = try OutputUndoRecord.capture(source: source, outputs: [output])
        try Data("keep".utf8).write(to: userFile)
        var trashed: [URL] = []
        try undo.undo { url in
            trashed.append(url)
            try FileManager.default.moveItem(at: url, to: directory.appendingPathComponent("trash-" + url.lastPathComponent))
        }
        #expect(trashed == [output])
        #expect(FileManager.default.fileExists(atPath: userFile.path))
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test func undoRejectsAParentFolderReplacedWithASymlink() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.txt")
        let folder = directory.appendingPathComponent("outputs")
        let moved = directory.appendingPathComponent("moved")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let output = folder.appendingPathComponent("output.txt")
        try Data("source".utf8).write(to: source)
        try Data("result".utf8).write(to: output)
        let undo = try OutputUndoRecord.capture(source: source, outputs: [output])
        try FileManager.default.moveItem(at: folder, to: moved)
        try FileManager.default.createSymbolicLink(at: folder, withDestinationURL: moved)
        #expect(throws: (any Error).self) { try undo.validate() }
    }

    @Test @MainActor func batchContinuesAfterAFileFailsAndReportsRealCompletion() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let broken = directory.appendingPathComponent("broken.pdf")
        let valid = directory.appendingPathComponent("valid.pdf")
        try Data("This is not a PDF".utf8).write(to: broken)
        var box = CGRect(x: 0, y: 0, width: 40, height: 40)
        let context = try #require(CGContext(valid as CFURL, mediaBox: &box, nil))
        context.beginPDFPage(nil); context.setFillColor(CGColor(gray: 0.5, alpha: 1)); context.fill(box); context.endPDFPage(); context.closePDF()
        let originals = try [Data(contentsOf: broken), Data(contentsOf: valid)]
        let shelf = GlassShelfModel(environment: EngineEnvironment())
        shelf.add([broken, valid]); shelf.selectedFormat = .png
        var successes: [URL] = []
        shelf.onCompleted = { input, _ in successes.append(input) }
        shelf.run()
        for _ in 0..<300 where shelf.isRunning { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!shelf.isRunning)
        #expect(shelf.completedCount == 2)
        #expect(shelf.progress == 1)
        #expect(successes == [valid])
        #expect(shelf.items[1].state == .complete)
        if case .failed = shelf.items[0].state {} else { Issue.record("Broken PDF did not retain its error") }
        #expect(shelf.completedResults.count == 1)
        #expect(shelf.completedResults[0].outputURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        #expect(try [Data(contentsOf: broken), Data(contentsOf: valid)] == originals)
    }

    @Test @MainActor func cancellingBeforeBatchStartsPublishesNothing() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("input.pdf")
        try Data("Sample".utf8).write(to: input)
        let shelf = GlassShelfModel(environment: EngineEnvironment())
        shelf.add([input]); shelf.selectedFormat = .png
        shelf.run(); shelf.cancel()
        for _ in 0..<100 where shelf.isRunning { try await Task.sleep(for: .milliseconds(10)) }
        #expect(shelf.items[0].state == .cancelled)
        #expect(shelf.completedResults.isEmpty)
        #expect(shelf.completedCount == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["input.pdf"])
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("FileOrbitAux-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
}
