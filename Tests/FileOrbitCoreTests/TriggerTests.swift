import Testing
import Foundation
@testable import FileOrbitCore

struct TriggerTests {
    @Test func testRequiresTwoCompleteTaps() {
        var detector = DoubleCommandDetector()
        let result1 = detector.handle(.commandDown, at: 1)
        #expect(!(result1))
        let result2 = detector.handle(.commandUp, at: 1.08)
        #expect(!(result2))
        let result3 = detector.handle(.commandDown, at: 1.20)
        #expect(!(result3))
        let result4 = detector.handle(.commandUp, at: 1.28)
        #expect(result4)
    }

    @Test func testExpiredFirstTapDoesNotTrigger() {
        var detector = DoubleCommandDetector()
        _ = detector.handle(.commandDown, at: 1)
        _ = detector.handle(.commandUp, at: 1.08)
        _ = detector.handle(.commandDown, at: 1.55)
        let result5 = detector.handle(.commandUp, at: 1.60)
        #expect(!(result5))
        _ = detector.handle(.commandDown, at: 1.70)
        let result6 = detector.handle(.commandUp, at: 1.75)
        #expect(result6)
    }

    @Test func testCommandChordCancelsBothTaps() {
        var detector = DoubleCommandDetector()
        _ = detector.handle(.commandDown, at: 1)
        _ = detector.handle(.commandUp, at: 1.05)
        _ = detector.handle(.commandDown, at: 1.15)
        _ = detector.handle(.interference, at: 1.18)
        let result7 = detector.handle(.commandUp, at: 1.2)
        #expect(!(result7))
        _ = detector.handle(.commandDown, at: 1.25)
        let result8 = detector.handle(.commandUp, at: 1.30)
        #expect(!(result8))
    }

    @Test func testInterveningClickOrModifierCancelsPendingTap() {
        var detector = DoubleCommandDetector()
        _ = detector.handle(.commandDown, at: 1)
        _ = detector.handle(.commandUp, at: 1.05)
        _ = detector.handle(.interference, at: 1.10)
        _ = detector.handle(.commandDown, at: 1.15)
        let result9 = detector.handle(.commandUp, at: 1.20)
        #expect(!(result9))
    }

    @Test func testLongHoldDoesNotCountAsTap() {
        var detector = DoubleCommandDetector()
        _ = detector.handle(.commandDown, at: 1)
        let result10 = detector.handle(.commandUp, at: 1.40)
        #expect(!(result10))
        _ = detector.handle(.commandDown, at: 1.45)
        let result11 = detector.handle(.commandUp, at: 1.50)
        #expect(!(result11))
    }

    @Test func testTripleTapOnlyTriggersOnce() {
        var detector = DoubleCommandDetector()
        var hits = 0
        for time in [1.0, 1.15, 1.30] {
            _ = detector.handle(.commandDown, at: time)
            if detector.handle(.commandUp, at: time + 0.05) { hits += 1 }
        }
        #expect(hits == 1)
    }

    @Test func testRepeatedDownInvalidatesGesture() {
        var detector = DoubleCommandDetector()
        _ = detector.handle(.commandDown, at: 1)
        _ = detector.handle(.commandDown, at: 1.01)
        _ = detector.handle(.commandUp, at: 1.05)
        _ = detector.handle(.commandDown, at: 1.15)
        let result12 = detector.handle(.commandUp, at: 1.2)
        #expect(!(result12))
    }

    @Test func testStrayUpDoesNotBecomeTap() {
        var detector = DoubleCommandDetector()
        _ = detector.handle(.commandUp, at: 1)
        _ = detector.handle(.commandDown, at: 1.1)
        let result13 = detector.handle(.commandUp, at: 1.15)
        #expect(!(result13))
    }

    @Test func testNonmonotonicOrInvalidTimeResetsGesture() {
        for invalidTime in [0.5, Double.nan, Double.infinity, -1] {
            var detector = DoubleCommandDetector()
            _ = detector.handle(.commandDown, at: 1)
            _ = detector.handle(.commandUp, at: 1.05)
            _ = detector.handle(.commandDown, at: invalidTime)
            let result14 = detector.handle(.commandUp, at: 1.20)
            #expect(!(result14))
        }
    }

    @Test func testResetDropsPendingTap() {
        var detector = DoubleCommandDetector()
        _ = detector.handle(.commandDown, at: 1)
        _ = detector.handle(.commandUp, at: 1.05)
        detector.reset()
        _ = detector.handle(.commandDown, at: 1.1)
        let result15 = detector.handle(.commandUp, at: 1.15)
        #expect(!(result15))
    }

    @Test func testTotalReleaseGapMustFitInterval() {
        var detector = DoubleCommandDetector(maximumInterval: 0.35, maximumHold: 0.3)
        _ = detector.handle(.commandDown, at: 1)
        _ = detector.handle(.commandUp, at: 1.05)
        _ = detector.handle(.commandDown, at: 1.35)
        let result16 = detector.handle(.commandUp, at: 1.55)
        #expect(!(result16))
    }
}
