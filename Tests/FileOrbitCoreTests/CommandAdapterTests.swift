import Foundation
import Testing
@testable import FileOrbitCore

struct CommandAdapterTests {
    private func recognized(_ events: [(UInt16, CommandModifierState, TimeInterval)]) -> Int {
        var adapter = CommandEventAdapter()
        var detector = DoubleCommandDetector()
        var count = 0
        for (key, modifiers, time) in events {
            if detector.handle(adapter.flagsChanged(keyCode: key, modifiers: modifiers), at: time) { count += 1 }
        }
        return count
    }

    @Test func steadyCapsLockDoesNotDisableDoubleCommand() {
        #expect(recognized([
            (55, [.command, .capsLock], 1), (55, [.capsLock], 1.05),
            (55, [.command, .capsLock], 1.15), (55, [.capsLock], 1.20)
        ]) == 1)
    }

    @Test func actualCapsLockTransitionBetweenTapsCancelsThePendingTap() {
        #expect(recognized([
            (55, [.command], 1), (55, [], 1.05),
            (57, [.capsLock], 1.10),
            (55, [.command, .capsLock], 1.15), (55, [.capsLock], 1.20)
        ]) == 0)
    }

    @Test func gestureCanRestartAfterCapsLockTransition() {
        #expect(recognized([
            (55, [.command], 1), (55, [], 1.05),
            (57, [.capsLock], 1.10),
            (55, [.command, .capsLock], 1.15), (55, [.capsLock], 1.20),
            (55, [.command, .capsLock], 1.30), (55, [.capsLock], 1.35)
        ]) == 1)
    }

    @Test func capsLockChangeWhileCommandHeldDoesNotBecomeATap() {
        #expect(recognized([
            (55, [.command], 1), (57, [.command, .capsLock], 1.02), (55, [.capsLock], 1.05),
            (55, [.command, .capsLock], 1.15), (55, [.capsLock], 1.20)
        ]) == 0)
    }

    @Test func aDifferentCommandReleaseCannotCompleteATap() {
        #expect(recognized([
            (55, [.command], 1), (54, [], 1.05),
            (55, [.command], 1.15), (55, [], 1.20)
        ]) == 0)
    }

    @Test func overlappingLeftAndRightCommandKeysCancelTheGesture() {
        #expect(recognized([
            (55, [.command], 1), (54, [.command], 1.02),
            (55, [.command], 1.04), (54, [], 1.06),
            (55, [.command], 1.15), (55, [], 1.20)
        ]) == 0)
    }

    @Test func cleanRightCommandTapsWork() {
        #expect(recognized([
            (54, [.command], 1), (54, [], 1.05),
            (54, [.command], 1.15), (54, [], 1.20)
        ]) == 1)
    }

    @Test func heldShiftAndCommandAreNeverIsolatedTaps() {
        #expect(recognized([
            (55, [.command, .shift], 1), (55, [.shift], 1.05),
            (55, [.command, .shift], 1.15), (55, [.shift], 1.20)
        ]) == 0)
    }

    @Test func resetDiscardsAnIncompletePress() {
        var adapter = CommandEventAdapter()
        var detector = DoubleCommandDetector()
        _ = detector.handle(adapter.flagsChanged(keyCode: 55, modifiers: [.command]), at: 1)
        adapter.reset(); detector.reset()
        _ = detector.handle(adapter.flagsChanged(keyCode: 55, modifiers: []), at: 1.05)
        _ = detector.handle(adapter.flagsChanged(keyCode: 55, modifiers: [.command]), at: 1.15)
        let result = detector.handle(adapter.flagsChanged(keyCode: 55, modifiers: []), at: 1.20)
        #expect(!result)
    }
}
