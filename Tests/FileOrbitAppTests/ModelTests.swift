import Foundation
import Testing
@testable import FileOrbit

@MainActor
struct ModelTests {
    @Test func invalidSelectionClearsThePreviouslySelectedFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("prior.txt")
        try Data("An earlier selection".utf8).write(to: file)
        let model = AppModel()
        model.select(file)
        #expect(model.input == file)
        model.select(directory)
        #expect(model.input == nil)
        #expect(model.actions.isEmpty)
        #expect(model.errorMessage != nil)
    }
}
