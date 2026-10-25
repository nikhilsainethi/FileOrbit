import AppKit
import SwiftUI

/// Shared optical-glass colors. Labels are opaque and never blurred with the backdrop.
enum OrbitPalette {
    static func primaryText(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.94, green: 0.95, blue: 0.97) : Color(red: 10.0/255, green: 92.0/255, blue: 96.0/255)
    }
    static func secondaryText(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.69, green: 0.74, blue: 0.78) : Color(red: 0.36, green: 0.42, blue: 0.45)
    }
    static func activeText(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.65, green: 0.98, blue: 0.94) : Color(red: 0.04, green: 0.36, blue: 0.38)
    }
    static func accent(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.14, green: 0.88, blue: 0.78) : Color(red: 30.0/255, green: 200.0/255, blue: 184.0/255)
    }
    static func baseWash(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.07, green: 0.08, blue: 0.11).opacity(0.72) : Color(white: 0.99).opacity(0.64)
    }
    static func opaqueSurface(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.12, green: 0.14, blue: 0.17) : Color(red: 0.96, green: 0.97, blue: 0.97)
    }
}

/// Apply to content whose frame already describes the desired surface:
/// `content.modifier(LiquidGlassStyle(shape: Circle(), active: isHovered))`.
/// The native backdrop is a sibling behind content, so text and icons stay sharp.
struct LiquidGlassStyle<S: Shape>: ViewModifier {
    let shape: S
    var active = false

    func body(content: Content) -> some View {
        content.background { LiquidGlassSurface(shape: shape, active: active) }
    }
}

/// Also available directly when a surface needs its own frame or a ZStack layer.
struct LiquidGlassSurface<S: Shape>: View {
    let shape: S
    var active = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var rim: AngularGradient {
        let colors: [Gradient.Stop] = scheme == .dark
            ? [.init(color: .white.opacity(0.32), location: 0), .init(color: .white.opacity(0.08), location: 0.5), .init(color: .white.opacity(0.32), location: 1)]
            : [.init(color: .white.opacity(0.95), location: 0), .init(color: .white.opacity(0.30), location: 0.375), .init(color: .black.opacity(0.10), location: 0.75), .init(color: .white.opacity(0.95), location: 1)]
        return AngularGradient(gradient: Gradient(stops: colors), center: .center, startAngle: .degrees(-90), endAngle: .degrees(270))
    }

    private var activeTint: RadialGradient {
        RadialGradient(colors: [OrbitPalette.accent(for: scheme).opacity(scheme == .dark ? 0.28 : 0.26), OrbitPalette.accent(for: scheme).opacity(0.04)], center: .topLeading, startRadius: 0, endRadius: 240)
    }

    private var activeRim: LinearGradient {
        LinearGradient(colors: [.white.opacity(0.9), OrbitPalette.accent(for: scheme).opacity(0.75), OrbitPalette.accent(for: scheme).opacity(0.35)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var surface: some View {
        ZStack {
            if scheme == .dark {
                // This 2pt stroke sits behind the fill and the centered 1pt rim,
                // leaving exactly a 0.5pt visible outer hairline.
                shape.stroke(.black.opacity(0.60), lineWidth: 2)
            }
            if reduceTransparency {
                shape.fill(OrbitPalette.opaqueSurface(for: scheme))
            } else {
                NativeGlassBackdrop(shape: shape, scheme: scheme)
                    .clipShape(shape)
                shape.fill(OrbitPalette.baseWash(for: scheme))
            }
            if active { shape.fill(activeTint) }
            shape.stroke(rim, lineWidth: contrast == .increased ? 1.5 : 1)
            if active { shape.stroke(activeRim, lineWidth: 1.5) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    var body: some View {
        Group {
            if scheme == .dark {
                surface
                    .shadow(color: .black.opacity(0.50), radius: 22, x: 0, y: 10)
                    .shadow(color: active ? Color.teal.opacity(0.35) : .clear, radius: active ? 14 : 0)
            } else {
                surface
                    .shadow(color: .black.opacity(0.07), radius: 5, x: 0, y: 3)
                    .shadow(color: .black.opacity(0.12), radius: 18, x: 0, y: 8)
            }
        }
    }
}

/// Public AppKit material API deliberately owns the blur kernel. No private filter
/// or foreground blur is used. An alpha mask also clips the actual native material,
/// instead of relying only on SwiftUI to clip an embedded AppKit view.
private struct NativeGlassBackdrop<S: Shape>: NSViewRepresentable {
    let shape: S
    let scheme: ColorScheme

    func makeNSView(context: Context) -> MaskedGlassEffectView {
        let view = MaskedGlassEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        configure(view)
        return view
    }
    func updateNSView(_ nsView: MaskedGlassEffectView, context: Context) { configure(nsView) }

    private func configure(_ view: MaskedGlassEffectView) {
        view.material = scheme == .dark ? .hudWindow : .popover
        view.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        view.pathProvider = { rect in shape.path(in: rect).cgPath }
        view.updateMask()
    }
}

private final class MaskedGlassEffectView: NSVisualEffectView {
    var pathProvider: ((CGRect) -> CGPath)?
    private var cachedPath: CGPath?
    private var cachedScale: CGFloat = 0
    private var cachedSize = CGSize.zero
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        updateMask()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateMask()
    }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateMask()
    }

    func updateMask() {
        guard bounds.width > 0, bounds.height > 0, let path = pathProvider?(CGRect(origin: .zero, size: bounds.size)) else { return }
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        guard cachedSize != bounds.size || cachedScale != scale || cachedPath != path else { return }
        let pixelWidth = max(1, Int(ceil(bounds.width * scale)))
        let pixelHeight = max(1, Int(ceil(bounds.height * scale)))
        guard let bitmap = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8,
                                     bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        // Shapes use SwiftUI's top-left origin; Quartz raster images use bottom-left.
        bitmap.translateBy(x: 0, y: CGFloat(pixelHeight))
        bitmap.scaleBy(x: scale, y: -scale)
        bitmap.addPath(path)
        bitmap.setFillColor(gray: 1, alpha: 1)
        bitmap.fillPath()
        guard let image = bitmap.makeImage() else { return }
        maskImage = NSImage(cgImage: image, size: bounds.size)
        cachedPath = path
        cachedScale = scale
        cachedSize = bounds.size
    }
}

#if FILEORBIT_XCODE_PREVIEWS
#Preview("Optical Daylight Quartz") {
    OpticalGlassPreview().preferredColorScheme(.light)
}
#Preview("Smoked Obsidian Crystal") {
    OpticalGlassPreview().preferredColorScheme(.dark)
}
private struct OpticalGlassPreview: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [.purple.opacity(0.3), .teal.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
            ZStack {
                ForEach(0..<6) { index in
                    let angle = OrbitLayout.angle(index: index, count: 6, compressionLast: false)
                    LiquidGlassSurface(shape: AnnularWedgeShape(centerAngle: angle, span: 60), active: index == 0)
                    Text(["PNG", "JPG", "HEIC", "Compress", "TIFF", "PDF"][index])
                        .font(.system(size: 11, weight: .semibold))
                        .position(OrbitLayout.labelPoint(index: index, count: 6, compressionLast: false))
                }
                Image(systemName: "doc.richtext")
                    .font(.system(size: 28, weight: .medium))
                    .frame(width: 104, height: 104)
                    .modifier(LiquidGlassStyle(shape: Circle()))
            }
            .frame(width: 384, height: 384)
        }
        .frame(width: 468, height: 468)
    }
}
#endif
