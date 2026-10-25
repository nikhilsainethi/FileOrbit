import AppKit
import SwiftUI
import Combine
import ImageIO


enum ClipboardOrbAction: String, CaseIterable, Identifiable, Sendable {
    case optimize, sanitize, webp, pin
    var id: String { rawValue }
    var title: String { switch self { case .optimize: "Optimize"; case .sanitize: "Sanitize"; case .webp: "WebP"; case .pin: "Pin" } }
    var symbol: String { switch self { case .optimize: "arrow.down.right.and.arrow.up.left"; case .sanitize: "eye.slash"; case .webp: "photo"; case .pin: "pin" } }
    var help: String {
        switch self {
        case .optimize: "Create a smaller image for the next paste"
        case .sanitize: "Review detected private information before replacing the clipboard"
        case .webp: "Convert the clipboard image to WebP"
        case .pin: "Keep this image in the local Notch Shelf"
        }
    }
}

@MainActor
final class ClipboardOrbModel: ObservableObject {
    @Published private(set) var snapshot: ClipboardSnapshot?
    @Published private(set) var thumbnail: NSImage?
    @Published private(set) var remaining = OrbLifetime.duration
    @Published private(set) var processing = false
    @Published private(set) var message: String?
    @Published private(set) var messageIsError = false
    @Published var expanded = false
    @Published var hovered = false
    var onAction: ((ClipboardOrbAction, ClipboardSnapshot) -> Void)?
    var onDismiss: (() -> Void)?
    private var lifetime = OrbLifetime(startedAt: ProcessInfo.processInfo.systemUptime)
    var progress: Double { min(1, max(0, remaining / OrbLifetime.duration)) }

    func present(_ snapshot: ClipboardSnapshot, at uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        self.snapshot = snapshot; processing = false; message = nil; messageIsError = false; hovered = false; expanded = false
        remaining = OrbLifetime.duration; lifetime = OrbLifetime(startedAt: uptime)
        thumbnail = Self.thumbnail(snapshot.data)
    }

    func hover(_ inside: Bool, at uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        hovered = inside; lifetime.setPaused(inside || processing, at: uptime)
        if inside { expanded = true }
    }

    func tick(at uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        lifetime.setPaused(hovered || processing, at: uptime)
        remaining = lifetime.remaining(at: uptime)
        return snapshot != nil && lifetime.isExpired(at: uptime)
    }

    func activate(_ action: ClipboardOrbAction) {
        guard !processing, let snapshot, let onAction else { return }
        processing = true; message = "Working locally…"; lifetime.setPaused(true, at: ProcessInfo.processInfo.systemUptime)
        onAction(action, snapshot)
    }

    /// Ignore completion from an operation belonging to a superseded snapshot.
    func finish(message: String, success: Bool = true, snapshotID: UUID? = nil) {
        if let snapshotID, snapshot?.id != snapshotID { return }
        processing = false; self.message = message; messageIsError = !success
        lifetime = OrbLifetime(startedAt: ProcessInfo.processInfo.systemUptime)
        lifetime.setPaused(hovered, at: ProcessInfo.processInfo.systemUptime)
        remaining = OrbLifetime.duration
    }

    func clear() { snapshot = nil; thumbnail = nil; processing = false; expanded = false; hovered = false; message = nil }

    private static func thumbnail(_ data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                                                        kCGImageSourceThumbnailMaxPixelSize: 128] as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))
    }
}

private final class ClipboardOrbPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ClipboardOrbWindowController {
    let model = ClipboardOrbModel()
    var onCancelProcessing: (() -> Void)?
    var onAction: ((ClipboardOrbAction, ClipboardSnapshot) -> Void)? {
        didSet { model.onAction = onAction }
    }
    private let sentinel: PasteboardSentinel
    private let preferences: SpatialPreferences
    private var panel: ClipboardOrbPanel?
    private var currentScreen: NSScreen?
    private var timer: Timer?
    private var subscriptions = Set<AnyCancellable>()
    private var keyboardMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var shrinkTask: Task<Void, Never>?

    init(sentinel: PasteboardSentinel, preferences: SpatialPreferences = .shared) {
        self.sentinel = sentinel; self.preferences = preferences
        model.onDismiss = { [weak self] in self?.dismiss() }
        model.$expanded.dropFirst().sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.resize() }
        }.store(in: &subscriptions)
        model.$hovered.dropFirst().sink { [weak self] inside in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.shrinkTask?.cancel()
                guard !inside, !self.model.processing else { return }
                self.shrinkTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(240))
                    guard !Task.isCancelled, let self, !self.model.hovered, !self.model.processing else { return }
                    self.model.expanded = false
                }
            }
        }.store(in: &subscriptions)
        preferences.$clipboardEnabled.dropFirst().sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshPreferences() }
        }.store(in: &subscriptions)
        preferences.$screenshotEnabled.dropFirst().sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshPreferences() }
        }.store(in: &subscriptions)
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.panel?.isVisible == true else { return }
                self.currentScreen = self.screen(at: NSEvent.mouseLocation); self.resize()
            }
        }
    }

    func show(snapshot: ClipboardSnapshot, at pointer: CGPoint? = nil) {
        // Existing user-triggered work retains its payload; a new paste must not
        // silently replace the review window's origin or the processing indicator.
        guard !model.processing else { return }
        currentScreen = screen(at: pointer ?? NSEvent.mouseLocation)
        model.present(snapshot)
        if panel == nil {
            let panel = ClipboardOrbPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "FileOrbit Clipboard Orb"; panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
            panel.level = .floating; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: ClipboardGlassOrbView(model: model))
            self.panel = panel
        }
        resize(); panel?.orderFrontRegardless()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.model.tick() { self.dismiss() }
            }
        }
        timer?.tolerance = 0.025
        installEscapeListener()
    }

    func finish(message: String, success: Bool = true, snapshotID: UUID? = nil) { model.finish(message: message, success: success, snapshotID: snapshotID) }

    func dismiss() {
        if model.processing { onCancelProcessing?() }
        timer?.invalidate(); timer = nil; shrinkTask?.cancel()
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }; keyboardMonitor = nil
        panel?.orderOut(nil); model.clear()
    }

    func refreshPreferences() {
        guard let snapshot = model.snapshot else { return }
        switch snapshot.origin {
        case .clipboard: if !preferences.clipboardEnabled { dismiss() }
        case .screenshot: if !preferences.screenshotEnabled { dismiss() }
        }
    }

    func stop() {
        dismiss()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }; screenObserver = nil
    }

    private func resize() {
        guard let panel, let screen = currentScreen ?? NSScreen.main else { return }
        let size: CGFloat = model.expanded ? 224 : 64
        let visible = screen.visibleFrame
        panel.setFrame(CGRect(x: visible.maxX - size - 22, y: visible.minY + 22, width: size, height: size), display: true)
    }

    private func screen(at point: CGPoint) -> NSScreen? { NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main }

    private func installEscapeListener() {
        guard keyboardMonitor == nil else { return }
        // Optional passive Escape dismissal. It never consumes the source app's key.
        keyboardMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            Task { @MainActor [weak self] in self?.dismiss() }
        }
    }
}

@MainActor
struct ClipboardGlassOrbView: View {
    @ObservedObject var model: ClipboardOrbModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var active: ClipboardOrbAction?

    var body: some View {
        ZStack {
            if model.expanded {
                ForEach(Array(ClipboardOrbAction.allCases.enumerated()), id: \.element.id) { index, action in
                    let angle = Double(index) * 90
                    let shape = MiniOrbSector(angle: angle)
                    Button { model.activate(action) } label: {
                        ZStack {
                            LiquidGlassSurface(shape: shape, active: active == action)
                            VStack(spacing: 4) {
                                Image(systemName: action.symbol).font(.system(size: 17, weight: .light))
                                Text(action.title).font(.system(size: 9, weight: .semibold))
                            }.position(labelPoint(index))
                        }.contentShape(shape)
                    }.buttonStyle(.plain).disabled(model.processing)
                        .help(action.help).accessibilityLabel(action.help)
                        .onHover { inside in active = inside ? action : nil }
                }
            }
            hub.frame(width: model.expanded ? 76 : 64, height: model.expanded ? 76 : 64)
                .position(x: model.expanded ? 112 : 32, y: model.expanded ? 112 : 32)
        }
        .frame(width: model.expanded ? 224 : 64, height: model.expanded ? 224 : 64)
        .foregroundStyle(OrbitPalette.primaryText(for: scheme))
        .onHover { model.hover($0) }
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.8), value: model.expanded)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.snapshot?.title ?? "Clipboard image")
    }

    private var hub: some View {
        ZStack {
            LiquidGlassSurface(shape: Circle(), active: model.processing)
            if model.processing { ProgressView().controlSize(.small) }
            else if let message = model.message {
                VStack(spacing: 3) {
                    Image(systemName: model.messageIsError ? "exclamationmark.triangle" : "checkmark").font(.system(size: 13, weight: .semibold))
                    Text(message).font(.system(size: 8)).lineLimit(3).multilineTextAlignment(.center).padding(.horizontal, 8)
                }.help(message)
            } else if let thumbnail = model.thumbnail {
                Image(nsImage: thumbnail).resizable().scaledToFill().frame(width: 39, height: 39).clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "sparkles").font(.system(size: 9, weight: .bold))
                            .foregroundStyle(OrbitPalette.accent(for: scheme)).padding(3).background(.regularMaterial, in: Circle()).offset(x: 5, y: 5)
                    }
            } else { Image(systemName: "sparkles").font(.system(size: 24, weight: .light)) }
            Circle().trim(from: 0, to: model.progress)
                .stroke(OrbitPalette.accent(for: scheme).opacity(0.8), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                .rotationEffect(.degrees(-90)).padding(3).allowsHitTesting(false)
        }.overlay(alignment: .topTrailing) {
            if model.expanded {
                Button { model.onDismiss?() } label: {
                    Image(systemName: "xmark").font(.system(size: 7, weight: .semibold)).padding(5).background(.regularMaterial, in: Circle())
                }.buttonStyle(.plain).accessibilityLabel("Dismiss clipboard suggestion")
            }
        }
    }

    private func labelPoint(_ index: Int) -> CGPoint {
        let radians = Double(index) * .pi / 2
        return CGPoint(x: 112 + sin(radians) * 77, y: 112 - cos(radians) * 77)
    }
}

private struct MiniOrbSector: Shape {
    let angle: Double
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY), radius = min(rect.width, rect.height) / 2 - 8
        let inner: CGFloat = 42
        let start = Angle.degrees(angle - 90 - 41), end = Angle.degrees(angle - 90 + 41)
        var path = Path()
        path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: center, radius: inner, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }
}

#if FILEORBIT_XCODE_PREVIEWS
#Preview("Clipboard Orb · Quartz") { OrbPreviewStage().preferredColorScheme(.light) }
#Preview("Clipboard Orb · Obsidian") { OrbPreviewStage().preferredColorScheme(.dark) }
@MainActor private struct OrbPreviewStage: View {
    @StateObject private var model = ClipboardOrbModel()
    var body: some View {
        ClipboardGlassOrbView(model: model).padding(30).frame(width: 300, height: 300)
            .onAppear { model.expanded = true }
    }
}
#endif
