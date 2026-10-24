import Foundation
import Testing
import SwiftUI
@testable import FileOrbit

struct OrbitGeometryTests {
    @Test func hoverSelectionUsesVisiblePetalsAndIgnoresClearSpace() {
        let center = CGPoint(x: 205, y: 205)
        for count in 1...7 {
            for compressionLast in [false, true] {
                for index in 0..<count {
                    let angle = OrbitLayout.angle(index: index, count: count, compressionLast: compressionLast)
                    let label = OrbitLayout.polar(radius: 149, degrees: angle, center: center)
                    #expect(OrbitLayout.actionIndex(at: label, count: count, compressionLast: compressionLast) == index)
                    let gap = OrbitLayout.polar(radius: 149, degrees: angle + OrbitLayout.span(count: count) / 2 + 2, center: center)
                    #expect(OrbitLayout.actionIndex(at: gap, count: count, compressionLast: compressionLast) == nil)
                }
                #expect(OrbitLayout.actionIndex(at: center, count: count, compressionLast: compressionLast) == nil)
                #expect(OrbitLayout.actionIndex(at: .zero, count: count, compressionLast: compressionLast) == nil)
            }
        }
        #expect(OrbitLayout.actionIndex(at: center, count: 0, compressionLast: false) == nil)
    }

    @Test func zeroSizedLayoutDoesNotCreateInvalidGeometry() {
        #expect(OrbitPetal(centerAngle: -90, span: 60).path(in: .zero).isEmpty)
    }

    @Test func keyboardSelectionWrapsAndHandlesMissingActions() {
        #expect(OrbitLayout.nextSelection(0, delta: -1, count: 5) == 4)
        #expect(OrbitLayout.nextSelection(4, delta: 1, count: 5) == 0)
        #expect(OrbitLayout.nextSelection(7, delta: 1, count: 0) == 0)
        #expect(OrbitLayout.nextSelection(8, delta: 1, count: 2) == 1)
    }

    @Test func compressionAlwaysOccupiesTheBottomPetal() {
        for count in 1...7 {
            #expect(OrbitLayout.angle(index: count - 1, count: count, compressionLast: true) == 90)
        }
    }

    @Test func petalsContainLabelsButLeaveHubAndGapsClear() {
        let rect = CGRect(x: 0, y: 0, width: 410, height: 410)
        for count in 1...7 {
            for index in 0..<count {
                let angle = OrbitLayout.angle(index: index, count: count, compressionLast: false)
                let shape = OrbitPetal(centerAngle: angle, span: OrbitLayout.span(count: count))
                let path = shape.path(in: rect)
                #expect(path.contains(OrbitLayout.polar(radius: 148, degrees: angle, center: CGPoint(x: 205, y: 205))))
                #expect(!path.contains(CGPoint(x: 205, y: 205)))
                #expect(!path.contains(CGPoint.zero))
                #expect(!path.contains(OrbitLayout.polar(radius: 148, degrees: angle + OrbitLayout.span(count: count) / 2 + 2, center: CGPoint(x: 205, y: 205))))
                #expect(path.boundingRect.minX >= 0 && path.boundingRect.maxX <= 410)
                #expect(path.boundingRect.minY >= 0 && path.boundingRect.maxY <= 410)
            }
        }
    }
}
