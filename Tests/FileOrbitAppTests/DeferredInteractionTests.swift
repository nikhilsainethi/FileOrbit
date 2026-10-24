import AppKit
import PDFKit
import Foundation
import Testing
import FileOrbitCore
@testable import FileOrbit

@MainActor struct DeferredInteractionTests {
    private func pdf() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("Three pages.pdf"), document = PDFDocument()
        for index in 0..<3 {
            let image = NSImage(size: NSSize(width: 80, height: 100), flipped: false) { rect in NSColor.white.setFill(); rect.fill(); return true }
            document.insert(try #require(PDFPage(image: image)), at: index)
        }
        #expect(document.write(to: url)); return url
    }
    @Test func clickBeforeMetadataWaitsAndThenOpensPDFPresets() async throws {
        let url = try pdf(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let model = AppModel(); model.select(url)
        let action = try #require(model.orbitActions.first { $0.id == "convert-png" })
        model.activate(action)
        #expect(model.stage == .ready)
        for _ in 0..<200 where model.parameterParentID == nil { try await Task.sleep(for: .milliseconds(5)) }
        #expect(model.parameterParentID == "convert-png")
        #expect(model.parameters.count == 3)
        #expect(model.stage == .ready)
    }
    @Test func dropTargetsRejectMoatsAndOutsideControls() throws {
        let url = try pdf(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let model = AppModel(); model.select(url)
        #expect(model.acceptsDrop(at: OrbitLayout.wheelCenter))
        #expect(!model.acceptsDrop(at: OrbitLayout.polar(radius: 56, degrees: 0, center: OrbitLayout.wheelCenter)))
        #expect(!model.acceptsDrop(at: CGPoint(x: 1, y: 1)))
        var openedShelf = false; model.onShelf = { _ in openedShelf = true }
        model.drop([url, url], at: CGPoint(x: 1, y: 1))
        #expect(!openedShelf)
    }
    @Test func closingRedactionDuringVerificationPreventsExport() async throws {
        let url = try pdf(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let editor = RedactionEditorModel(input: url)
        for _ in 0..<200 where editor.isLoading { try await Task.sleep(for: .milliseconds(5)) }
        #expect(editor.pageCount == 3)
        editor.add(CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2))
        var exported = false
        editor.export { _ in exported = true }
        #expect(editor.isVerifying)
        editor.cancel()
        try await Task.sleep(for: .milliseconds(200))
        #expect(!exported)
        #expect(!editor.isVerifying)
        editor.export { _ in exported = true }
        #expect(!exported)
    }
}
