import AppKit
import SwiftUI
import Combine

@MainActor
final class NotchPortalModel: ObservableObject {
    @Published var expanded = false
    @Published var showsShelf = false
    @Published var isDragging = false
    @Published var hovered = false
    @Published var pipelineTitle = "Optimize · WebP · Copy"
    @Published var status: String?
    @Published var processing = false
    @Published var hasHardwareNotch = false
    @Published var collapsedWidth: CGFloat = 180
    var onStash: (([URL]) -> Void)?
    var onPipeline: (([URL]) -> Void)?
    var onClose: (() -> Void)?
    var onCancelPipeline: (() -> Void)?
    var width: CGFloat { expanded ? 340 : collapsedWidth }
    var height: CGFloat { expanded ? (showsShelf ? 266 : 96) : 28 }
    func toggleShelf() { showsShelf.toggle(); expanded = true }
}

private final class NotchPortalPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The app delegate forwards only verified current Finder drags to this controller.
/// This class does not install another keyboard or global mouse listener.
@MainActor
final class NotchPortalWindowController {
    let model = NotchPortalModel()
    let stash: NotchStashModel
    var onPipeline: (([URL], String) -> Void)?
    var onCancelPipeline: (() -> Void)?
    private let preferences: SpatialPreferences
    private var panel: NotchPortalPanel?
    private var subscriptions = Set<AnyCancellable>()
    private var screenObserver: NSObjectProtocol?
    private var currentScreen: NSScreen?
    private var collapseTask: Task<Void, Never>?
    private var demoVisible = false

    init(preferences: SpatialPreferences = .shared, stash: NotchStashModel? = nil) {
        self.preferences = preferences; self.stash = stash ?? NotchStashModel()
        model.onStash = { [weak self] urls in self?.pin(urls) }
        model.onPipeline = { [weak self] urls in
            guard let self, !self.model.processing else { return }
            guard !self.preferences.favoritePipelineID.isEmpty, let onPipeline = self.onPipeline else {
                self.model.status = "Choose a favorite pipeline in Studio first."; return
            }
            self.model.processing = true; self.model.status = "Running locally…"
            onPipeline(urls, self.preferences.favoritePipelineID)
        }
        model.onClose = { [weak self] in self?.close() }
        model.onCancelPipeline = { [weak self] in self?.onCancelPipeline?() }
        model.$expanded.combineLatest(model.$showsShelf).dropFirst().sink { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.resize() }
        }.store(in: &subscriptions)
        model.$hovered.dropFirst().sink { [weak self] inside in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if inside { self.collapseTask?.cancel() }
                else if !self.model.isDragging { self.scheduleCollapse() }
            }
        }.store(in: &subscriptions)
        preferences.$notchEnabled.dropFirst().sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshPreferences() }
        }.store(in: &subscriptions)
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.panel?.isVisible == true else { return }
                self.currentScreen = self.screen(at: NSEvent.mouseLocation); self.resize()
            }
        }
    }

    func refreshPreferences() {
        guard preferences.notchEnabled else { if !demoVisible { close() }; return }
        if panel?.isVisible != true { show(at: NSEvent.mouseLocation) }
    }

    func dragBegan(urls: [URL], at pointer: CGPoint) {
        guard preferences.notchEnabled, !urls.isEmpty else { return }
        collapseTask?.cancel(); model.isDragging = true; model.expanded = true
        show(at: pointer)
    }

    func dragMoved(at pointer: CGPoint) {
        guard preferences.notchEnabled, model.isDragging, let screen = screen(at: pointer),
              currentScreen?.frame != screen.frame else { return }
        currentScreen = screen; resize(); panel?.orderFrontRegardless()
    }

    func dragEnded() {
        model.isDragging = false
        scheduleCollapse()
    }

    func showDemo(at pointer: CGPoint? = nil) {
        demoVisible = true; model.expanded = true; model.status = "Drop a sample to try the portal."
        show(at: pointer ?? NSEvent.mouseLocation)
    }

    func pin(_ urls: [URL]) {
        stash.add(urls); model.showsShelf = true; model.expanded = true
        model.status = stash.message ?? "Pinned \(stash.items.count) file\(stash.items.count == 1 ? "" : "s"). Originals stay in place."
        if panel?.isVisible != true { demoVisible = !preferences.notchEnabled; show(at: NSEvent.mouseLocation) }
    }

    @discardableResult
    func pin(_ snapshot: ClipboardSnapshot) throws -> URL {
        let url = try stash.pin(snapshot)
        model.showsShelf = true; model.expanded = true; model.status = "Clipboard image pinned locally."
        if panel?.isVisible != true { demoVisible = !preferences.notchEnabled; show(at: NSEvent.mouseLocation) }
        return url
    }

    func pipelineFinished(message: String) {
        model.processing = false; model.status = message
        if !model.hovered { scheduleCollapse() }
    }

    func close() {
        collapseTask?.cancel(); panel?.orderOut(nil)
        model.isDragging = false; model.expanded = false; model.showsShelf = false
        demoVisible = false
    }

    func stop() {
        close()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }; screenObserver = nil
    }

    private func show(at pointer: CGPoint) {
        currentScreen = screen(at: pointer)
        if panel == nil {
            let panel = NotchPortalPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "FileOrbit Liquid Notch"
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: LiquidNotchView(model: model, stash: stash))
            self.panel = panel
        }
        resize(); panel?.orderFrontRegardless()
    }

    private func resize() {
        guard let screen = currentScreen ?? NSScreen.main, let panel else { return }
        let snapshot = PortalScreen(frame: screen.frame, safeTop: screen.safeAreaInsets.top,
                                    topLeft: screen.auxiliaryTopLeftArea, topRight: screen.auxiliaryTopRightArea)
        let layout = NotchPortalGeometry.layout(on: snapshot, expanded: model.expanded, shelfVisible: model.showsShelf)
        let collapsed = NotchPortalGeometry.layout(on: snapshot, expanded: false, shelfVisible: false)
        model.hasHardwareNotch = layout.hasHardwareNotch; model.collapsedWidth = collapsed.frame.width
        // Controls begin below the camera cutout. SwiftUI animates the actual glass
        // surface; the transparent host is resized immediately for accurate drops.
        panel.setFrame(layout.frame, display: true)
    }

    private func scheduleCollapse() {
        collapseTask?.cancel()
        guard !model.isDragging, !model.processing, !model.showsShelf else { return }
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(850))
            guard !Task.isCancelled, let self, !self.model.hovered, !self.model.isDragging,
                  !self.model.processing, !self.model.showsShelf else { return }
            self.model.expanded = false; self.model.status = nil
        }
    }

    private func screen(at point: CGPoint) -> NSScreen? { NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main }
}
