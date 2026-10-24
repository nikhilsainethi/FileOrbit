import AppKit
import Testing
@testable import FileOrbit

struct PanelPlacementTests {
    @Test func clampsAllCornersOnASecondaryDisplay() {
        let screen = CGRect(x: -1920, y: 120, width: 1920, height: 1050)
        let size = OrbitLayout.canvasSize
        for point in [CGPoint(x: -1920, y: 120), CGPoint(x: 0, y: 120), CGPoint(x: -1920, y: 1170), CGPoint(x: 0, y: 1170)] {
            let origin = OrbitPanelPlacement.origin(size: size, visibleFrame: screen, anchor: point)
            #expect(origin.x >= screen.minX + 12)
            #expect(origin.y >= screen.minY + 12)
            #expect(origin.x + size.width <= screen.maxX - 12)
            #expect(origin.y + size.height <= screen.maxY - 12)
        }
    }
    @Test func centersWithoutAPointerAnchor() {
        let origin = OrbitPanelPlacement.origin(size: CGSize(width: 468, height: 500), visibleFrame: CGRect(x: 100, y: 80, width: 1000, height: 800), anchor: nil)
        #expect(origin == CGPoint(x: 366, y: 230))
    }
    @Test func smallVisibleFrameNeverInvertsClampBounds() {
        let origin = OrbitPanelPlacement.origin(size: CGSize(width: 468, height: 500), visibleFrame: CGRect(x: -200, y: 0, width: 400, height: 400), anchor: CGPoint(x: -100, y: 100))
        #expect(origin == CGPoint(x: -200, y: 0))
    }
}
