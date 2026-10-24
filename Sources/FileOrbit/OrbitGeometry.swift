import SwiftUI

/// Drawing and input geometry in literal points, with y increasing downwards.
/// Angles increase clockwise; -90 degrees is the top of the wheel.
enum OrbitLayout {
    static let hubRadius: CGFloat = 52
    static let innerRadius: CGFloat = 60
    static let outerRadius: CGFloat = 138
    static let secondaryInnerRadius: CGFloat = 146
    static let secondaryOuterRadius: CGFloat = 192
    static let labelRadius: CGFloat = 99
    static let secondaryLabelRadius: CGFloat = 169
    static let activeScale: CGFloat = 1.03
    static let activeOffset: CGFloat = 6
    static let gap: CGFloat = 6

    // The canvas reserves clear space for the optional secondary ring and shadows.
    // The primary visible wheel, including an active sector, is only 296.28pt wide.
    static let canvasSize = CGSize(width: 468, height: 508)
    static let wheelFrame = CGRect(x: 42, y: 36, width: 384, height: 384)
    static let wheelCenter = CGPoint(x: wheelFrame.width / 2, y: wheelFrame.height / 2)
    static let center = CGPoint(x: wheelFrame.midX, y: wheelFrame.midY)
    static let hubFrame = CGRect(x: center.x - hubRadius, y: center.y - hubRadius, width: 104, height: 104)
    static let captionFrame = CGRect(x: 84, y: center.y + outerRadius * activeScale + activeOffset + 16, width: 300, height: 26)
    static let expandedCaptionFrame = CGRect(x: 84, y: center.y + secondaryOuterRadius * activeScale + activeOffset + 16, width: 300, height: 26)
    static let closeFrame = CGRect(x: 416, y: 20, width: 28, height: 28)
    static let cardFrame = CGRect(x: 54, y: 54, width: 360, height: 392)
    static let workingFrame = CGRect(x: center.x - 122, y: center.y - 122, width: 244, height: 244)

    static func nextSelection(_ current: Int, delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        // Reduce both operands before adding, avoiding overflow for large inputs.
        let remainder = current % count
        let normalized = remainder < 0 ? remainder + count : remainder
        let step = delta % count
        if step >= 0 { return normalized >= count - step ? normalized - (count - step) : normalized + step }
        return normalized < -step ? count - (-step - normalized) : normalized + step
    }

    static func angle(index: Int, count: Int, compressionLast: Bool) -> Double {
        let step = 360 / Double(max(1, count))
        return compressionLast ? 90 + Double(index - count + 1) * step : -90 + Double(index) * step
    }

    /// Gap width is applied in the shape as parallel offsets, never subtracted here.
    static func span(count: Int) -> Double {
        guard count > 0 else { return 0 }
        return count == 1 ? 110 : 360 / Double(count)
    }

    static func polar(radius: CGFloat, degrees: Double, center: CGPoint) -> CGPoint {
        CGPoint(x: center.x + radius * cos(degrees * .pi / 180), y: center.y + radius * sin(degrees * .pi / 180))
    }

    /// Label positions, like actionIndex's pointer input, are wheel-local.
    static func labelPoint(index: Int, count: Int, compressionLast: Bool, radius: CGFloat = labelRadius) -> CGPoint {
        polar(radius: radius, degrees: angle(index: index, count: count, compressionLast: compressionLast), center: wheelCenter)
    }

    static func activeTransform(angle: Double, center: CGPoint = wheelCenter) -> CGAffineTransform {
        let offset = polar(radius: activeOffset, degrees: angle, center: .zero)
        return CGAffineTransform(a: activeScale, b: 0, c: 0, d: activeScale,
                                 tx: center.x * (1 - activeScale) + offset.x,
                                 ty: center.y * (1 - activeScale) + offset.y)
    }

    static func actionPath(index: Int, count: Int, compressionLast: Bool, activeIndex: Int? = nil,
                           in rect: CGRect = CGRect(origin: .zero, size: wheelFrame.size)) -> Path {
        guard count > 0, (0..<count).contains(index) else { return Path() }
        let degrees = angle(index: index, count: count, compressionLast: compressionLast)
        let path = AnnularWedgeShape(centerAngle: degrees, span: span(count: count)).path(in: rect)
        return index == activeIndex ? path.applying(activeTransform(angle: degrees, center: CGPoint(x: rect.midX, y: rect.midY))) : path
    }

    /// Selects only the rendered path, including the active sector's exact transform.
    /// The caller must pass the same activeIndex it uses for drawing.
    static func actionIndex(at point: CGPoint, count: Int, compressionLast: Bool, activeIndex: Int? = nil) -> Int? {
        guard count > 0 else { return nil }
        if let activeIndex, (0..<count).contains(activeIndex),
           actionPath(index: activeIndex, count: count, compressionLast: compressionLast, activeIndex: activeIndex).contains(point) {
            return activeIndex
        }
        return (0..<count).first { index in
            index != activeIndex && actionPath(index: index, count: count, compressionLast: compressionLast).contains(point)
        }
    }

    static func readyPath(actionCount: Int, compressionLast: Bool, activeIndex: Int? = nil) -> Path {
        var path = Path(ellipseIn: hubFrame)
        for index in 0..<max(0, actionCount) {
            path.addPath(actionPath(index: index, count: actionCount, compressionLast: compressionLast, activeIndex: activeIndex, in: wheelFrame))
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

/// An annular sector bounded by two lines parallel to its radial boundaries.
/// Each line is inset by gap/2, yielding a constant gap between adjacent sectors.
/// Four true circular fillets meet both the side lines and concentric arcs tangentially.
/// Radii are points, independent of rect size; rect supplies only the center.
struct AnnularWedgeShape: Shape {
    var centerAngle: Double
    var span: Double
    var innerRadius: CGFloat = 60
    var outerRadius: CGFloat = 138
    var gap: CGFloat = 6
    var outerCornerRadius: CGFloat = 14
    var innerCornerRadius: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        guard rect.width > 0, rect.height > 0, rect.width.isFinite, rect.height.isFinite,
              rect.origin.x.isFinite, rect.origin.y.isFinite,
              centerAngle.isFinite, span.isFinite, span > 0, span <= 360,
              innerRadius.isFinite, outerRadius.isFinite, innerRadius > 0, outerRadius > innerRadius,
              gap.isFinite, gap >= 0, outerCornerRadius.isFinite, innerCornerRadius.isFinite else { return Path() }

        let inset = gap / 2
        let halfSine = CGFloat(sin(min(span / 2, 90) * .pi / 180))
        guard inset < innerRadius * halfSine else { return Path() }
        let halfWidth = (outerRadius - innerRadius) / 2
        // Clamp only when explicitly requested dimensions cannot accommodate a fillet.
        // The standard primary and secondary sectors retain their full 14/10pt radii.
        let outerLimit = (outerRadius * halfSine - inset) / (1 + halfSine)
        let innerLimit = halfSine < 1 ? (innerRadius * halfSine - inset) / (1 - halfSine) : halfWidth
        let outerCorner = max(0, min(outerCornerRadius, halfWidth, outerLimit))
        let innerCorner = max(0, min(innerCornerRadius, halfWidth, innerLimit))
        let outerCenterRadius = outerRadius - outerCorner
        let innerCenterRadius = innerRadius + innerCorner
        let outerInset = asin((inset + outerCorner) / outerCenterRadius) * 180 / .pi
        let innerInset = asin((inset + innerCorner) / innerCenterRadius) * 180 / .pi
        let normalizedCenter = centerAngle.truncatingRemainder(dividingBy: 360)
        let start = normalizedCenter - span / 2, end = normalizedCenter + span / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        func point(_ radius: CGFloat, _ degrees: Double) -> CGPoint {
            OrbitLayout.polar(radius: radius, degrees: degrees, center: center)
        }
        let outerStartCenter = point(outerCenterRadius, start + outerInset)
        let outerEndCenter = point(outerCenterRadius, end - outerInset)
        let innerStartCenter = point(innerCenterRadius, start + innerInset)
        let innerEndCenter = point(innerCenterRadius, end - innerInset)
        func cornerPoint(_ cornerCenter: CGPoint, _ radius: CGFloat, _ degrees: Double) -> CGPoint {
            OrbitLayout.polar(radius: radius, degrees: degrees, center: cornerCenter)
        }
        let path = CGMutablePath()
        func arc(center: CGPoint, radius: CGFloat, start: Double, end: Double, clockwise: Bool) {
            // Break at cardinal extrema so Core Graphics' cubic arc representation
            // retains the exact circle bounds as well as tangent continuity.
            var cursor = start
            while abs(end - cursor) > 0.000000001 {
                let boundary = (clockwise ? ceil(cursor / 90) - 1 : floor(cursor / 90) + 1) * 90
                let next = clockwise ? max(end, boundary) : min(end, boundary)
                path.addArc(center: center, radius: radius, startAngle: cursor * .pi / 180,
                            endAngle: next * .pi / 180, clockwise: clockwise)
                cursor = next
            }
        }
        path.move(to: point(outerRadius, start + outerInset))
        arc(center: center, radius: outerRadius, start: start + outerInset, end: end - outerInset, clockwise: false)
        if outerCorner > 0 {
            arc(center: outerEndCenter, radius: outerCorner, start: end - outerInset, end: end + 90, clockwise: false)
        }
        path.addLine(to: cornerPoint(innerEndCenter, innerCorner, end + 90))
        if innerCorner > 0 {
            arc(center: innerEndCenter, radius: innerCorner, start: end + 90, end: end - innerInset + 180, clockwise: false)
        }
        arc(center: center, radius: innerRadius, start: end - innerInset, end: start + innerInset, clockwise: true)
        if innerCorner > 0 {
            arc(center: innerStartCenter, radius: innerCorner, start: start + innerInset + 180, end: start + 270, clockwise: false)
        }
        path.addLine(to: cornerPoint(outerStartCenter, outerCorner, start - 90))
        if outerCorner > 0 {
            arc(center: outerStartCenter, radius: outerCorner, start: start - 90, end: start + outerInset, clockwise: false)
        }
        path.closeSubpath()
        return Path(path)
    }
}

/// Source-compatible name for existing orbit callers; all dimensions are now points.
struct OrbitPetal: Shape {
    var centerAngle: Double
    var span: Double
    var innerRadius: CGFloat = 60
    var outerRadius: CGFloat = 138
    var cornerRadius: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        AnnularWedgeShape(centerAngle: centerAngle, span: span, innerRadius: innerRadius, outerRadius: outerRadius,
                          outerCornerRadius: cornerRadius, innerCornerRadius: min(10, cornerRadius)).path(in: rect)
    }
}
