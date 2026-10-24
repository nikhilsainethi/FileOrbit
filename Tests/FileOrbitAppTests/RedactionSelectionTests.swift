import Foundation
import Testing
@testable import FileOrbit

struct RedactionSelectionTests {
    @Test func selectionNormalizesReverseDragAndClampsToDisplayedPage() {
        let result = RedactionSelection.normalized(from: CGPoint(x: 200, y: 400), to: CGPoint(x: -30, y: 100), size: CGSize(width: 400, height: 800))
        #expect(result == CGRect(x: 0, y: 0.125, width: 0.5, height: 0.375))
    }
    @Test func clicksAndNonFiniteCoordinatesCannotBecomeRedactions() {
        #expect(RedactionSelection.normalized(from: .zero, to: CGPoint(x: 2, y: 10), size: CGSize(width: 400, height: 800)) == nil)
        #expect(RedactionSelection.normalized(from: .zero, to: CGPoint(x: CGFloat.nan, y: 10), size: CGSize(width: 400, height: 800)) == nil)
    }
}
