import Foundation
import Testing
import SwiftUI
@testable import FileOrbit

struct OrbitGeometryTests {
    @Test func hoverSelectionUsesVisiblePetalsAndIgnoresClearSpace() {
        let center = CGPoint(x: 192, y: 192)
        for count in 1...7 {
            for compressionLast in [false, true] {
                for index in 0..<count {
                    let angle = OrbitLayout.angle(index: index, count: count, compressionLast: compressionLast)
                    let label = OrbitLayout.polar(radius: 99, degrees: angle, center: center)
                    #expect(OrbitLayout.actionIndex(at: label, count: count, compressionLast: compressionLast) == index)
                    let gap = OrbitLayout.polar(radius: 99, degrees: angle + OrbitLayout.span(count: count) / 2, center: center)
                    #expect(OrbitLayout.actionIndex(at: gap, count: count, compressionLast: compressionLast) == nil)
                }
                #expect(OrbitLayout.actionIndex(at: center, count: count, compressionLast: compressionLast) == nil)
                #expect(OrbitLayout.actionIndex(at: .zero, count: count, compressionLast: compressionLast) == nil)
            }
        }
        #expect(OrbitLayout.actionIndex(at: center, count: 0, compressionLast: false) == nil)
    }

    @Test func wheelUsesCompactPhysicalDimensions() {
        #expect(OrbitLayout.hubFrame.size == CGSize(width: 104, height: 104))
        #expect(OrbitLayout.wheelFrame.size == CGSize(width: 384, height: 384))
        let path = OrbitPetal(centerAngle: -90, span: 120).path(in: CGRect(x: 0, y: 0, width: 384, height: 384))
        #expect(abs(path.boundingRect.minY - 54) < 0.0001)
        #expect(!path.contains(CGPoint(x: 192, y: 133)))
        #expect(path.contains(CGPoint(x: 192, y: 131)))
    }

    @Test func radialSidesHaveConstantSixPointGaps() {
        let center = CGPoint(x: 192, y: 192)
        let rect = CGRect(origin: .zero, size: CGSize(width: 384, height: 384))
        for count in 2...7 {
            let span = OrbitLayout.span(count: count)
            let angle = OrbitLayout.angle(index: 0, count: count, compressionLast: false)
            let path = OrbitPetal(centerAngle: angle, span: span).path(in: rect)
            let boundary = (angle + span / 2) * .pi / 180
            let inward = CGVector(dx: sin(boundary), dy: -cos(boundary))
            for radius: CGFloat in [80, 100, 120] {
                let edge = OrbitLayout.polar(radius: radius, degrees: angle + span / 2, center: center)
                let inside = CGPoint(x: edge.x + inward.dx * 3.01, y: edge.y + inward.dy * 3.01)
                let gap = CGPoint(x: edge.x + inward.dx * 2.99, y: edge.y + inward.dy * 2.99)
                #expect(path.contains(inside))
                #expect(!path.contains(gap))
            }
        }
    }

    @Test func circularFilletsMeetEveryEdgeTangentially() {
        let rect = CGRect(x: 0, y: 0, width: 384, height: 384)
        for count in 1...7 {
            for radii: (CGFloat, CGFloat) in [(60, 138), (146, 192)] {
                let path = AnnularWedgeShape(centerAngle: -90, span: OrbitLayout.span(count: count), innerRadius: radii.0, outerRadius: radii.1).path(in: rect)
                var cursor = CGPoint.zero
                var beginning = CGPoint.zero
                var tangents: [(CGVector, CGVector)] = []
                func vector(_ a: CGPoint, _ b: CGPoint) -> CGVector { CGVector(dx: b.x - a.x, dy: b.y - a.y) }
                func length(_ a: CGVector) -> CGFloat { hypot(a.dx, a.dy) }
                path.forEach { element in
                    switch element {
                    case .move(to: let p): cursor = p; beginning = p
                    case .line(to: let p):
                        let v = vector(cursor, p)
                        if length(v) > 0.000001 { tangents.append((v, v)) }
                        cursor = p
                    case .quadCurve:
                        Issue.record("Fillets must be circular arcs, not quadratic corner approximations")
                    case .curve(to: let p, control1: let c1, control2: let c2):
                        tangents.append((vector(cursor, c1), vector(c2, p)))
                        cursor = p
                    case .closeSubpath:
                        let v = vector(cursor, beginning)
                        if length(v) > 0.000001 { tangents.append((v, v)) }
                    }
                }
                #expect(tangents.count >= 8)
                for i in tangents.indices {
                    let a = tangents[i].1
                    let b = tangents[(i + 1) % tangents.count].0
                    let cosine = (a.dx * b.dx + a.dy * b.dy) / (length(a) * length(b))
                    #expect(abs(cosine - 1) < 0.000001)
                }
            }
        }
    }

    @Test func filletRadiiAreFourteenOutsideAndTenInside() {
        let center = OrbitLayout.wheelCenter
        let path = AnnularWedgeShape(centerAngle: -45, span: 90).path(in: CGRect(origin: .zero, size: OrbitLayout.wheelFrame.size))
        var cursor = CGPoint.zero
        var sides: [(CGPoint, CGPoint)] = []
        path.forEach { element in
            switch element {
            case .move(to: let p): cursor = p
            case .line(to: let p):
                if hypot(p.x - cursor.x, p.y - cursor.y) > 1 { sides.append((cursor, p)) }
                cursor = p
            case .curve(to: let p, control1: _, control2: _): cursor = p
            case .quadCurve(to: let p, control: _): cursor = p
            case .closeSubpath: break
            }
        }
        #expect(sides.count == 2)
        guard let side = sides.first else { return }
        // The first side lies three points above the horizontal radial boundary.
        // Its tangent points locate circles 14/10pt inwards from that side.
        #expect(abs(side.0.y - (center.y - 3)) < 0.000001)
        #expect(abs(side.1.y - (center.y - 3)) < 0.000001)
        let outerCircleCenter = CGPoint(x: side.0.x, y: side.0.y - 14)
        let innerCircleCenter = CGPoint(x: side.1.x, y: side.1.y - 10)
        #expect(abs(hypot(outerCircleCenter.x - center.x, outerCircleCenter.y - center.y) - (138 - 14)) < 0.000001)
        #expect(abs(hypot(innerCircleCenter.x - center.x, innerCircleCenter.y - center.y) - (60 + 10)) < 0.000001)
    }

    @Test func activeHitTestingTracksDisplacementWithoutKeepingTheOldHitArea() {
        let center = OrbitLayout.wheelCenter
        let angle = OrbitLayout.angle(index: 0, count: 6, compressionLast: false)
        let liftedOuterPoint = OrbitLayout.polar(radius: 145, degrees: angle, center: center)
        let vacatedInnerPoint = OrbitLayout.polar(radius: 63, degrees: angle, center: center)
        #expect(OrbitLayout.actionIndex(at: liftedOuterPoint, count: 6, compressionLast: false) == nil)
        #expect(OrbitLayout.actionIndex(at: liftedOuterPoint, count: 6, compressionLast: false, activeIndex: 0) == 0)
        #expect(OrbitLayout.actionIndex(at: vacatedInnerPoint, count: 6, compressionLast: false) == 0)
        #expect(OrbitLayout.actionIndex(at: vacatedInnerPoint, count: 6, compressionLast: false, activeIndex: 0) == nil)
        for active in 0..<6 {
            for index in 0..<6 {
                let point = OrbitLayout.labelPoint(index: index, count: 6, compressionLast: false)
                #expect(OrbitLayout.actionIndex(at: point, count: 6, compressionLast: false, activeIndex: active) == index)
            }
        }
    }

    @Test func primaryFootprintAndCaptionClearanceRespectTheSpecification() {
        #expect((OrbitLayout.outerRadius * OrbitLayout.activeScale + OrbitLayout.activeOffset) * 2 <= 310)
        #expect(OrbitLayout.innerRadius - OrbitLayout.hubRadius == 8)
        #expect(OrbitLayout.secondaryInnerRadius - OrbitLayout.outerRadius == 8)
        #expect(OrbitLayout.captionFrame.height == 26)
        #expect(OrbitLayout.expandedCaptionFrame.height == 26)
        #expect(abs(OrbitLayout.captionFrame.minY - (OrbitLayout.center.y + 138 * 1.03 + 6) - 16) < 0.000001)
        #expect(abs(OrbitLayout.expandedCaptionFrame.minY - (OrbitLayout.center.y + 192 * 1.03 + 6) - 16) < 0.000001)
        let path = OrbitLayout.readyPath(actionCount: 7, compressionLast: true, activeIndex: 6)
        #expect(CGRect(origin: .zero, size: OrbitLayout.canvasSize).contains(path.boundingRect))
    }

    @Test func shapeDimensionsAreLiteralPointsAcrossDifferentContainers() {
        let a = AnnularWedgeShape(centerAngle: -90, span: 90).path(in: CGRect(x: 0, y: 0, width: 384, height: 384)).boundingRect
        let b = AnnularWedgeShape(centerAngle: -90, span: 90).path(in: CGRect(x: 100, y: 150, width: 500, height: 500)).boundingRect
        #expect(abs(a.width - b.width) < 0.000001)
        #expect(abs(a.height - b.height) < 0.000001)
        #expect(abs((b.midX - a.midX) - 158) < 0.000001)
        #expect(abs((b.midY - a.midY) - 208) < 0.000001)
    }

    @Test func degenerateDimensionsNeverGenerateNonfinitePaths() {
        let rect = CGRect(x: 0, y: 0, width: 384, height: 384)
        #expect(AnnularWedgeShape(centerAngle: .nan, span: 60).path(in: rect).isEmpty)
        #expect(AnnularWedgeShape(centerAngle: 0, span: 0).path(in: rect).isEmpty)
        #expect(AnnularWedgeShape(centerAngle: 0, span: 361).path(in: rect).isEmpty)
        #expect(AnnularWedgeShape(centerAngle: 0, span: 0.1).path(in: rect).isEmpty)
        #expect(AnnularWedgeShape(centerAngle: 0, span: 60, innerRadius: 138, outerRadius: 60).path(in: rect).isEmpty)
        #expect(AnnularWedgeShape(centerAngle: 0, span: 60, gap: 500).path(in: rect).isEmpty)
        #expect(OrbitLayout.span(count: 0) == 0)
    }

    @Test func zeroSizedLayoutDoesNotCreateInvalidGeometry() {
        #expect(OrbitPetal(centerAngle: -90, span: 60).path(in: .zero).isEmpty)
    }

    @Test func keyboardSelectionWrapsAndHandlesMissingActions() {
        #expect(OrbitLayout.nextSelection(0, delta: -1, count: 5) == 4)
        #expect(OrbitLayout.nextSelection(4, delta: 1, count: 5) == 0)
        #expect(OrbitLayout.nextSelection(7, delta: 1, count: 0) == 0)
        #expect(OrbitLayout.nextSelection(8, delta: 1, count: 2) == 1)
        #expect(OrbitLayout.nextSelection(Int.max - 1, delta: Int.max - 1, count: Int.max) == Int.max - 2)
        #expect(OrbitLayout.nextSelection(Int.min, delta: -1, count: 7) == 5)
    }

    @Test func compressionAlwaysOccupiesTheBottomPetal() {
        for count in 1...7 {
            #expect(OrbitLayout.angle(index: count - 1, count: count, compressionLast: true) == 90)
        }
    }

    @Test func petalsContainLabelsButLeaveHubAndGapsClear() {
        let rect = CGRect(x: 0, y: 0, width: 384, height: 384)
        for count in 1...7 {
            for index in 0..<count {
                let angle = OrbitLayout.angle(index: index, count: count, compressionLast: false)
                let shape = OrbitPetal(centerAngle: angle, span: OrbitLayout.span(count: count))
                let path = shape.path(in: rect)
                #expect(path.contains(OrbitLayout.polar(radius: 99, degrees: angle, center: CGPoint(x: 192, y: 192))))
                #expect(!path.contains(CGPoint(x: 192, y: 192)))
                #expect(!path.contains(CGPoint.zero))
                #expect(!path.contains(OrbitLayout.polar(radius: 99, degrees: angle + OrbitLayout.span(count: count) / 2, center: CGPoint(x: 192, y: 192))))
                #expect(path.boundingRect.minX >= 0 && path.boundingRect.maxX <= 384)
                #expect(path.boundingRect.minY >= 0 && path.boundingRect.maxY <= 384)
            }
        }
    }
}
