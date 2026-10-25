import Testing
import Foundation
import CoreGraphics
@testable import FileOrbit

struct SpatialSurfaceTests {
    @Test func notchFrameHonorsNegativeDisplayOriginsAndCutout() {
        let screen = PortalScreen(frame: CGRect(x: -1728, y: 120, width: 1728, height: 1117), safeTop: 32,
                                  topLeft: CGRect(x: -1728, y: 1205, width: 750, height: 32),
                                  topRight: CGRect(x: -750, y: 1205, width: 750, height: 32))
        let layout = NotchPortalGeometry.layout(on: screen, expanded: true, shelfVisible: false)
        #expect(layout.frame.width == 340)
        #expect(layout.frame.height == 96)
        #expect(layout.frame.midX == -864)
        #expect(layout.frame.maxY == 1205)
        #expect(layout.frame.minX >= screen.frame.minX)
        #expect(layout.hasHardwareNotch)
    }

    @Test func externalDisplayGetsSmallPill() {
        let screen = PortalScreen(frame: CGRect(x: 300, y: -900, width: 1440, height: 900), safeTop: 0, topLeft: nil, topRight: nil)
        let layout = NotchPortalGeometry.layout(on: screen, expanded: false, shelfVisible: false)
        #expect(layout.frame == CGRect(x: 930, y: -28, width: 180, height: 28))
        #expect(!layout.hasHardwareNotch)
    }

    @Test func invalidAuxiliaryRectsDoNotShiftControlsOffscreen() {
        let screen = PortalScreen(frame: CGRect(x: 0, y: 0, width: 1024, height: 768), safeTop: 24,
                                  topLeft: CGRect(x: 0, y: 744, width: 400, height: 24),
                                  topRight: CGRect(x: 3000, y: 744, width: 100, height: 24))
        let layout = NotchPortalGeometry.layout(on: screen, expanded: true, shelfVisible: true)
        #expect(layout.frame.midX == 512)
        #expect(layout.frame.maxY == 744)
        #expect(layout.frame.minY >= 0)
    }

    @Test func clipboardGateIgnoresOwnWritesAndRequiresSameRevision() {
        var gate = ClipboardRevisionGate(initial: 8)
        let observation1 = gate.observe(8)
        #expect(!observation1)
        let observation2 = gate.observe(9)
        #expect(observation2)
        gate.didWrite(10)
        let observation3 = gate.observe(10)
        #expect(!observation3)
        #expect(!gate.canCommit(expected: 9, current: 10))
        #expect(gate.canCommit(expected: 10, current: 10))
        let observation4 = gate.observe(11)
        #expect(observation4)
    }

    @Test func lifetimePauseRetainsRemainingTime() {
        var lifetime = OrbLifetime(startedAt: 100)
        #expect(lifetime.remaining(at: 102) == 2.5)
        lifetime.setPaused(true, at: 102)
        #expect(lifetime.remaining(at: 500) == 2.5)
        lifetime.setPaused(false, at: 500)
        #expect(lifetime.remaining(at: 501) == 1.5)
        #expect(lifetime.isExpired(at: 502.5))
    }

    @Test func screenshotGateRejectsOldDuplicatesAndUnstableFiles() {
        var gate = ScreenshotObservationGate(startedAt: Date(timeIntervalSince1970: 100))
        let url = URL(fileURLWithPath: "/tmp/new-screen.png")
        let observation5 = gate.observe(url: url, created: Date(timeIntervalSince1970: 99), bytes: 10, modified: 101)
        #expect(!observation5)
        let observation6 = gate.observe(url: url, created: Date(timeIntervalSince1970: 101), bytes: 10, modified: 101)
        #expect(!observation6)
        let observation7 = gate.observe(url: url, created: Date(timeIntervalSince1970: 101), bytes: 20, modified: 102)
        #expect(!observation7)
        let observation8 = gate.observe(url: url, created: Date(timeIntervalSince1970: 101), bytes: 20, modified: 102)
        #expect(observation8)
        let observation9 = gate.observe(url: url, created: Date(timeIntervalSince1970: 101), bytes: 20, modified: 102)
        #expect(!observation9)
    }
    @Test func screenshotHistoryEvictionDoesNotReplayOldFiles() {
        var gate = ScreenshotObservationGate(startedAt: Date(timeIntervalSince1970: 100))
        let first = URL(fileURLWithPath: "/tmp/screen-0.png")
        for index in 0..<514 {
            let url = URL(fileURLWithPath: "/tmp/screen-\(index).png")
            let date = Date(timeIntervalSince1970: Double(101 + index))
            _ = gate.observe(url: url, created: date, bytes: 10, modified: date.timeIntervalSince1970)
            let delivered = gate.observe(url: url, created: date, bytes: 10, modified: date.timeIntervalSince1970)
            #expect(delivered)
        }
        let firstRepeat = gate.observe(url: first, created: Date(timeIntervalSince1970: 101), bytes: 10, modified: 101)
        let secondRepeat = gate.observe(url: first, created: Date(timeIntervalSince1970: 101), bytes: 10, modified: 101)
        #expect(!firstRepeat && !secondRepeat)
    }

    @Test func vanishedIncompleteScreenshotsCannotBlockNewCaptures() {
        var gate = ScreenshotObservationGate(startedAt: Date(timeIntervalSince1970: 100))
        for index in 0..<64 {
            _ = gate.observe(url: URL(fileURLWithPath: "/tmp/vanished-\(index).png"),
                             created: Date(timeIntervalSince1970: 101), bytes: 10, modified: 101)
        }
        let new = URL(fileURLWithPath: "/tmp/usable-capture.png")
        let first = gate.observe(url: new, created: Date(timeIntervalSince1970: 110), bytes: 30, modified: 110)
        let stable = gate.observe(url: new, created: Date(timeIntervalSince1970: 110), bytes: 30, modified: 110)
        #expect(!first)
        #expect(stable)
    }

}
