import Testing
import Foundation
@testable import FileOrbit

@Suite @MainActor struct NeuralReviewModelTests {
    @Test func noExportCanOccurWithoutASnapshotEvenIfReviewIsChecked() {
        let model = SanitizeReviewModel(input: URL(fileURLWithPath: "/synthetic.pdf"), autoLoad: false)
        model.reviewed = true
        #expect(!model.canExport)
        model.add(CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        #expect(model.regions.isEmpty)
        model.cancel()
        #expect(!model.reviewed && !model.canExport && model.document == nil && model.image == nil)
    }
}
