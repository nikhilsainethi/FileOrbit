import SwiftUI

/// Shared drawing and input geometry. All coordinates are top-down, in points.
enum OrbitLayout {
    static let canvasSize = CGSize(width: 468, height: 500)
    static let wheelFrame = CGRect(x: 29, y: 17, width: 410, height: 410)
    static let hubFrame = CGRect(x: 151, y: 139, width: 166, height: 166)
    static let captionFrame = CGRect(x: 84, y: 440, width: 300, height: 36)
    static let closeFrame = CGRect(x: 427, y: 9, width: 28, height: 28)
    static let cardFrame = CGRect(x: 54, y: 54, width: 360, height: 392)
    static let workingFrame = CGRect(x: 89, y: 105, width: 290, height: 290)

    static func nextSelection(_ current: Int, delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((current % count + delta) % count + count) % count
    }
    static func angle(index: Int, count: Int, compressionLast: Bool) -> Double {
        let step = 360 / Double(max(1, count))
        return compressionLast ? 90 + Double(index - count + 1) * step : -90 + Double(index) * step
    }
    static func span(count: Int) -> Double { min(count == 1 ? 110 : 145, 360 / Double(max(1, count)) - 7) }
    static func polar(radius: CGFloat, degrees: Double, center: CGPoint) -> CGPoint {
        CGPoint(x: center.x + radius * cos(degrees * .pi / 180), y: center.y + radius * sin(degrees * .pi / 180))
    }
    /// A pointer in the 410-point wheel only selects a rendered petal. Transparent
    /// gaps, the file hub, and the square bounds around the orbit are not actions.
    static func actionIndex(at point: CGPoint, count: Int, compressionLast: Bool) -> Int? {
        guard count > 0 else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: 410, height: 410)
        return (0..<count).first { index in
            OrbitPetal(centerAngle: angle(index: index, count: count, compressionLast: compressionLast), span: span(count: count))
                .path(in: bounds).contains(point)
        }
    }

    static func readyPath(actionCount: Int, compressionLast: Bool) -> Path {
        var path = Path(ellipseIn: hubFrame)
        for index in 0..<max(0, actionCount) {
            path.addPath(OrbitPetal(centerAngle: angle(index: index, count: actionCount, compressionLast: compressionLast), span: span(count: actionCount)).path(in: wheelFrame))
        }
        path.addPath(Capsule().path(in: captionFrame))
        path.addPath(Path(ellipseIn: closeFrame))
        return path
    }
    static var compressionPath: Path { readyPath(actionCount: 3, compressionLast: false) }
    static func interactivePath(stage: AppModel.Stage, actionCount: Int, compressionLast: Bool, hasInput: Bool) -> Path {
        switch stage {
        case .ready where hasInput && actionCount > 0: return readyPath(actionCount: actionCount, compressionLast: compressionLast)
        case .compression: return compressionPath
        case .working: return Path(ellipseIn: workingFrame)
        default:
            var path = RoundedRectangle(cornerRadius: 32).path(in: cardFrame)
            path.addPath(Path(ellipseIn: closeFrame))
            return path
        }
    }
}

/// A rounded annular sector; the same path is used to render and hit-test a petal.
struct OrbitPetal: Shape {
    var centerAngle: Double
    var span: Double
    var innerRadius: CGFloat = 94
    var outerRadius: CGFloat = 203
    var cornerRadius: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        guard rect.width > 0, rect.height > 0 else { return Path() }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let scale = min(rect.width, rect.height) / 410
        let outer = outerRadius * scale, inner = innerRadius * scale
        let corner = min(cornerRadius * scale, (outer - inner) / 2)
        let start = centerAngle - span / 2, end = centerAngle + span / 2
        let outerInset = Double(corner / outer) * 180 / .pi
        let innerInset = min(Double(corner / inner) * 180 / .pi, span / 3)
        func point(_ radius: CGFloat, _ angle: Double) -> CGPoint { OrbitLayout.polar(radius: radius, degrees: angle, center: center) }
        var path = Path()
        path.move(to: point(outer, start + outerInset))
        path.addArc(center: center, radius: outer, startAngle: .degrees(start + outerInset), endAngle: .degrees(end - outerInset), clockwise: false)
        path.addQuadCurve(to: point(outer - corner, end), control: point(outer, end))
        path.addLine(to: point(inner + corner, end))
        path.addQuadCurve(to: point(inner, end - innerInset), control: point(inner, end))
        path.addArc(center: center, radius: inner, startAngle: .degrees(end - innerInset), endAngle: .degrees(start + innerInset), clockwise: true)
        path.addQuadCurve(to: point(inner + corner, start), control: point(inner, start))
        path.addLine(to: point(outer - corner, start))
        path.addQuadCurve(to: point(outer, start + outerInset), control: point(outer, start))
        path.closeSubpath()
        return path
    }
}
