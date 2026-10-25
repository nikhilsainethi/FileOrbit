import AppKit
import SwiftUI
import FileOrbitCore
import OSLog
import Quartz
import Combine

enum FileOrbitRuntime {
    static var isPreview: Bool { Bundle.main.object(forInfoDictionaryKey: "FileOrbitPreview") as? Bool == true || ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" }
    private static let previewLogger = Logger(subsystem: "io.fileorbit.preview", category: "Panel")
    static func recordPreview(_ event: String) { if isPreview { previewLogger.notice("\(event, privacy: .public)") } }
    static func appearance(for value: String) -> NSAppearance? {
        switch value { case "light": return NSAppearance(named: .aqua); case "dark": return NSAppearance(named: .darkAqua); default: return nil }
    }
    static var displayName: String { isPreview ? "FileOrbit Preview" : "FileOrbit" }
}
enum OrbitPanelPlacement {
    static func origin(size: CGSize, visibleFrame: CGRect, anchor: CGPoint?) -> CGPoint {
        let center = anchor ?? CGPoint(x: visibleFrame.midX, y: visibleFrame.midY)
        func clamp(_ desired: CGFloat, minimum: CGFloat, maximum: CGFloat, extent: CGFloat) -> CGFloat {
            guard maximum - minimum >= extent + 24 else { return minimum }
            return min(max(desired, minimum + 12), maximum - extent - 12)
        }
        return CGPoint(x: clamp(center.x - size.width / 2, minimum: visibleFrame.minX, maximum: visibleFrame.maxX, extent: size.width),
                       y: clamp(center.y - size.height / 2, minimum: visibleFrame.minY, maximum: visibleFrame.maxY, extent: size.height))
    }
    static func wheelOrigin(visibleFrame: CGRect, pointer: CGPoint) -> CGPoint {
        // Convert the top-down SwiftUI hub center into AppKit's bottom-up space.
        let anchor = CGPoint(x: pointer.x + OrbitLayout.canvasSize.width / 2 - OrbitLayout.center.x,
                             y: pointer.y + OrbitLayout.center.y - OrbitLayout.canvasSize.height / 2)
        return origin(size: OrbitLayout.canvasSize, visibleFrame: visibleFrame, anchor: anchor)
    }
}
final class OrbitPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = AppModel()
    private let shelf = GlassShelfModel()
    private let hud = JobHUDModel()
    private let monitor = CommandMonitor()
    private let dragMonitor = FinderDragMonitor()
    private lazy var commercial = CommercialCoordinator(model: model)
    private var onboarding: OnboardingSandboxWindow?
    private var loupeDemoWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var studio: NSPopover?
    private var studioWindow: NSWindow?
    private var panel: OrbitPanel?
    private var shelfPanel: OrbitPanel?
    private var hudPanel: OrbitPanel?
    private var settingsWindow: NSWindow?
    private var redactionWindow: NSWindow?
    private var redactionEditor: RedactionEditorModel?
    private var quickLookWindow: NSWindow?
    private var outsideClick: Any?
    private var panelKeyboard: Any?
    private var activationObserver: NSObjectProtocol?
    private var subscriptions = Set<AnyCancellable>()
    private var hideGeneration = UUID()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = FileOrbitRuntime.appearance(for: StudioPreferences.shared.appearance)
        NSApp.setActivationPolicy(FileOrbitRuntime.isPreview || CommandLine.arguments.contains("--ui-test") ? .regular : .accessory)
        createStatusItem()
        commercial.start()
        model.onNotchDemo = { [weak self] in self?.commercial.notch.showDemo() }
        model.onOrbDemo = { [weak self] in self?.commercial.showOrbDemo() }
        model.onLoupeDemo = { [weak self] in self?.showLoupeDemo() }
        model.onOnboarding = { [weak self] in self?.showOnboarding() }
        if !FileOrbitRuntime.isPreview { NSApp.servicesProvider = self }
        model.onSettings = { [weak self] in self?.showSettings() }
        model.onDismiss = { [weak self] in self?.model.showLoupe(false); self?.model.isDraggingFile = false; self?.panel?.orderOut(nil) }
        model.onShelf = { [weak self] urls in self?.showShelf(urls) }
        model.onRoute = { [weak self] command, url in self?.route(command, url: url) }
        model.onRedact = { [weak self] url in self?.showRedaction(url) }
        model.onRunStarted = { [weak self] input in
            guard let self else { return }
            self.hud.setRunning(input: input); self.hud.onCancel = { [weak self] in self?.model.cancel() }; self.showHUD()
            guard !self.model.neuralBusy else { return }
            let generation = UUID(); self.hideGeneration = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + (NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.18)) {
                guard self.hideGeneration == generation else { return }; self.panel?.orderOut(nil)
            }
        }
        model.onRunCompleted = { [weak self] input, result in
            guard let self else { return }
            self.hud.complete(input: input, result: result)
            let id = UUID(); self.hud.impactID = id
            ImpactStore.shared.record(id: id, category: self.model.impactCategory, inputBytes: result.inputBytes, outputBytes: result.outputBytes)
            self.showHUD()
        }
        model.onRunFailed = { [weak self] error in
            guard let self else { return }; self.hud.fail(error); self.model.errorMessage = nil; self.showHUD()
        }
        hud.onQuickLook = { [weak self] in if let url = self?.hud.result?.outputURLs.first { self?.showQuickLook(url) } }
        shelf.onCompleted = { [weak self] input, result in
            JobHistory.shared.record(input: input, result: result)
            ImpactStore.shared.record(id: UUID(), category: self?.shelf.mode == .compress ? .compression : .conversion, inputBytes: result.inputBytes, outputBytes: result.outputBytes)
        }
        shelf.$isPinned.dropFirst().sink { [weak self] pinned in self?.shelfPanel?.level = pinned ? .floating : .normal }.store(in: &subscriptions)
        StudioPreferences.shared.$appearance.dropFirst().sink { value in NSApp.appearance = FileOrbitRuntime.appearance(for: value) }.store(in: &subscriptions)
        monitor.onGesture = { [weak self] in self?.handleFinderGesture() }
        dragMonitor.onDragMoved = { [weak self] point in self?.commercial.notch.dragMoved(at: point) }
        dragMonitor.onDragBegan = { [weak self] urls, point in self?.commercial.notch.dragBegan(urls: urls, at: point) }
        dragMonitor.onSpace = { [weak self] held in self?.model.showLoupe(held) }
        dragMonitor.onReveal = { [weak self] urls, mode in
            guard let self, self.model.stage != .working, let first = urls.first else { return }
            self.model.select(first); self.model.setMode(mode); self.model.isDraggingFile = true
            self.showPanel(nearPointer: true, activate: false)
        }
        dragMonitor.onMode = { [weak self] mode in self?.model.setMode(mode) }
        dragMonitor.onEnd = { [weak self] in self?.model.isDraggingFile = false; self?.commercial.notch.dragEnded() }
        if !FileOrbitRuntime.isPreview { monitor.start(); dragMonitor.start() }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.monitor.reset(); self?.model.refresh()
                if !FileOrbitRuntime.isPreview { self?.monitor.start(); self?.dragMonitor.start() }
            }
        }
        outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.model.stage != .working, !FileOrbitRuntime.isPreview else { return }
            self.panel?.orderOut(nil)
        }
        panelKeyboard = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            if self.model.isDraggingFile, let held = FinderDragKey.spaceState(for: event) {
                self.model.showLoupe(held); return nil
            }
            if event.type == .flagsChanged, event.window === self.panel || self.panel?.isKeyWindow == true {
                self.model.updateModifiers(event.modifierFlags); return event
            }
            if event.type == .keyDown, event.keyCode == 49, event.window === self.hudPanel, self.hud.phase == .complete {
                self.hud.quickLook(); return nil
            }
            guard event.type == .keyDown, let panel = self.panel,
                  event.window === panel || (event.window == nil && panel.isKeyWindow), event.keyCode == 53,
                  event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return event }
            if self.model.parameterParentID != nil { self.model.parameterParentID = nil; self.model.selectedParameterID = nil }
            else if self.model.stage != .working { panel.orderOut(nil) }
            return nil
        }
        if let index = CommandLine.arguments.firstIndex(of: "--open"), CommandLine.arguments.indices.contains(index + 1) {
            model.select(URL(fileURLWithPath: CommandLine.arguments[index + 1])); showPanel(nearPointer: false)
        } else if FileOrbitRuntime.isPreview || !UserDefaults.standard.bool(forKey: "FileOrbit.hasLaunched") {
            UserDefaults.standard.set(true, forKey: "FileOrbit.hasLaunched"); showOnboarding()
        }
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        if urls.count > 1 { showShelf(urls) }
        else if let url = urls.first { model.select(url); showPanel(nearPointer: false) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showPanel(nearPointer: false) }
        return true
    }
    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let symbol = NSImage(systemSymbolName: "circle.hexagongrid", accessibilityDescription: "FileOrbit Studio"); symbol?.isTemplate = true
        item.button?.image = symbol; item.button?.target = self; item.button?.action = #selector(statusClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        let menu = NSMenu()
        if FileOrbitRuntime.isPreview {
            let notice = NSMenuItem(title: "Preview · installed FileOrbit stays unchanged", action: nil, keyEquivalent: ""); notice.isEnabled = false; menu.addItem(notice); menu.addItem(.separator())
        }
        for (title, action, key) in [("Open Wheel", #selector(openPanel), ""), ("Choose Files…", #selector(chooseFile), "o"), ("Glass Shelf", #selector(openShelf), ""), ("Studio", #selector(openStudio), ""), ("Settings…", #selector(settings), ","), ("Quit " + FileOrbitRuntime.displayName, #selector(quit), "q")] {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: key); entry.target = self; menu.addItem(entry)
        }
        statusMenu = menu; statusItem = item
        do {
            let main = NSMenu(), application = NSMenuItem(title: FileOrbitRuntime.displayName, action: nil, keyEquivalent: "")
            application.submenu = menu.copy() as? NSMenu; main.addItem(application)
            let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""), editMenu = NSMenu(title: "Edit")
            for (title, action, key) in [("Undo", Selector(("undo:")), "z"), ("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] {
                editMenu.addItem(withTitle: title, action: action, keyEquivalent: key)
            }
            edit.submenu = editMenu; main.addItem(edit)
            let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: ""), windowMenu = NSMenu(title: "Window")
            windowMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
            windowItem.submenu = windowMenu; main.addItem(windowItem)
            NSApp.windowsMenu = windowMenu; NSApp.mainMenu = main
        }
    }
    @objc private func statusClicked() {
        guard let button = statusItem?.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp, let statusMenu { statusMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button) }
        else { showStudio() }
    }
    @objc private func openStudio() { showStudio(inWindow: true) }
    private func showStudio(inWindow: Bool = false) {
        panel?.orderOut(nil)
        if studio?.isShown == true { studio?.performClose(nil); return }
        model.refresh()
        var descriptors = Dictionary(uniqueKeysWithValues: OrbitMode.allCases.map { ($0.rawValue, model.orbitActions(for: $0).map(\.descriptor)) })
        if model.input == nil {
            descriptors["modify"] = CapabilityCatalog.modificationActions(for: URL(fileURLWithPath: "/FileOrbit-example.pdf"), environment: model.environment).map { OrbitAction($0).descriptor }
            descriptors["quickActions"] = [.init(id: "shelf", title: "Shelf", symbol: "tray.2"), .init(id: "airdrop", title: "AirDrop", symbol: "airplayaudio"), .init(id: "copy-path", title: "Copy Path", symbol: "link"), .init(id: "terminal", title: "Terminal", symbol: "terminal")]
            descriptors["convert"] = [StudioActionDescriptor(id: "convert-png", title: "PNG", symbol: "photo"), .init(id: "convert-jpg", title: "JPG", symbol: "photo.fill"), .init(id: "convert-webp", title: "WebP", symbol: "photo"), .init(id: "convert-pdf", title: "PDF", symbol: "doc.richtext"), .init(id: "compress", title: "Compress", symbol: "arrow.down.right.and.arrow.up.left")]
        }
        let content = MenuBarStudioPopover(preferences: .shared, descriptorsByMode: descriptors, onOpenSettings: { [weak self] in self?.studio?.performClose(nil); self?.showSettings() }, onOpenShelf: { [weak self] in self?.studio?.performClose(nil); self?.showShelf([]) })
        if inWindow || statusItem?.button?.window == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 355, height: 530), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "FileOrbit Studio"; window.isReleasedWhenClosed = false
            let hosting = NSHostingView(rootView: ScrollView { content }.frame(width: 355, height: 540))
            hosting.sizingOptions = []; hosting.safeAreaRegions = []
            window.contentView = hosting; window.setContentSize(NSSize(width: 355, height: 540)); window.contentMinSize = NSSize(width: 355, height: 540); window.center()
            studioWindow?.close(); studioWindow = window; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard let button = statusItem?.button else { return }
        let popover = NSPopover(); popover.behavior = .transient; popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let controller = NSHostingController(rootView: ScrollView { content }.frame(width: 355, height: 540))
        controller.sizingOptions = []; controller.preferredContentSize = NSSize(width: 355, height: 540)
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: 355, height: 540)
        studio = popover; NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
    @objc private func openPanel() { model.refresh(); if model.stage != .working { model.back() }; showPanel(nearPointer: false) }
    @objc private func chooseFile() { showPanel(nearPointer: false); model.chooseFile() }
    @objc private func openShelf() { showShelf([]) }
    @objc private func settings() { showSettings() }
    @objc private func quit() {
        if model.stage == .working || shelf.isRunning {
            let alert = NSAlert(); alert.messageText = "Files are still processing"; alert.informativeText = "Cancel the active operation in the notification or shelf before quitting."; alert.addButton(withTitle: "Return to FileOrbit"); alert.runModal()
            if shelf.isRunning { showShelf([]) } else { showHUD() }
        } else { NSApp.terminate(nil) }
    }
    private func handleFinderGesture() {
        ShortcutDiagnostics.record("handling Finder gesture")
        guard model.stage != .working else { showHUD(); return }
        do { model.select(try FinderSelection.selectedFile()) } catch { model.selectionFailed(error.localizedDescription) }
        showPanel(nearPointer: true)
    }
    private func makePanel<Content: View>(size: CGSize, title: String, content: Content) -> OrbitPanel {
        let created = OrbitPanel(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let hosting = NSHostingView(rootView: content); hosting.sizingOptions = []; hosting.safeAreaRegions = []
        created.contentView = hosting; created.isOpaque = false; created.backgroundColor = .clear; created.hasShadow = false
        created.level = .floating; created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        created.isReleasedWhenClosed = false; created.hidesOnDeactivate = false; created.acceptsMouseMovedEvents = true; created.title = title
        return created
    }
    private func showPanel(nearPointer: Bool, activate: Bool = true) {
        hideGeneration = UUID()
        if panel == nil { panel = makePanel(size: OrbitLayout.canvasSize, title: FileOrbitRuntime.displayName, content: OrbitView(model: model)) }
        guard let panel else { return }
        let pointer = NSEvent.mouseLocation, visible = screen(at: pointer).visibleFrame
        panel.setFrameOrigin(nearPointer ? OrbitPanelPlacement.wheelOrigin(visibleFrame: visible, pointer: pointer) : OrbitPanelPlacement.origin(size: panel.frame.size, visibleFrame: visible, anchor: nil))
        if activate { panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
        else { panel.orderFrontRegardless() }
        FileOrbitRuntime.recordPreview("Panel shown")
    }
    private func screen(at point: CGPoint) -> NSScreen { NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main ?? NSScreen.screens[0] }
    private func showHUD() {
        if hudPanel == nil { hudPanel = makePanel(size: CGSize(width: 348, height: 102), title: "FileOrbit activity", content: TransientHUDToastView(model: hud, onClose: { [weak self] in self?.hudPanel?.orderOut(nil) }).padding(24)) }
        guard let hudPanel else { return }
        let visible = screen(at: NSEvent.mouseLocation).visibleFrame
        hudPanel.setFrameOrigin(CGPoint(x: visible.maxX - hudPanel.frame.width - 8, y: visible.maxY - hudPanel.frame.height - 6))
        hudPanel.orderFrontRegardless()
    }
    private func showShelf(_ urls: [URL]) {
        shelf.environment = .discover(); shelf.add(urls)
        if shelfPanel == nil {
            shelfPanel = makePanel(size: CGSize(width: 288, height: 328), title: "FileOrbit Glass Shelf", content: FloatingGlassShelfView(model: shelf, onClose: { [weak self] in self?.shelfPanel?.orderOut(nil) }).padding(24))
            shelfPanel?.isMovableByWindowBackground = true
            shelfPanel?.level = shelf.isPinned ? .floating : .normal
            let visible = screen(at: NSEvent.mouseLocation).visibleFrame
            shelfPanel?.setFrameOrigin(CGPoint(x: visible.maxX - 316, y: visible.midY - 164))
        }
        guard let shelfPanel else { return }
        let target = shelfPanel.frame
        if let panel, panel.isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let hub = CGRect(x: panel.frame.minX + OrbitLayout.hubFrame.minX, y: panel.frame.minY + OrbitLayout.canvasSize.height - OrbitLayout.hubFrame.maxY, width: 104, height: 104)
            shelfPanel.setFrame(hub, display: false); shelfPanel.alphaValue = 0; shelfPanel.orderFrontRegardless(); panel.orderOut(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.24; context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                shelfPanel.animator().setFrame(target, display: true); shelfPanel.animator().alphaValue = 1
            }
        } else { panel?.orderOut(nil) }
        shelfPanel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    private func showRedaction(_ url: URL) {
        panel?.orderOut(nil)
        redactionEditor?.cancel(); redactionWindow?.close()
        let editor = RedactionEditorModel(input: url); redactionEditor = editor
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 760, height: 730), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "FileOrbit · Redact a copy"; window.isReleasedWhenClosed = false; window.delegate = self
        window.contentView = NSHostingView(rootView: RedactionEditorView(model: editor, onExport: { [weak self, weak window] regions in
            guard let self else { return }
            guard self.model.stage != .working else { editor.error = "Another file is still processing. Finish or cancel it, then save this redacted copy."; return }
            self.model.select(url)
            guard self.model.input == url else { editor.error = self.model.errorMessage ?? "The source could not be opened."; return }
            window?.close(); self.model.run(.redactPDF(regions))
        }, onCancel: { [weak window] in editor.cancel(); window?.close() }))
        window.center(); redactionWindow = window; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    private func showQuickLook(_ url: URL) {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 760, height: 620), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = url.lastPathComponent; window.isReleasedWhenClosed = false
        if let preview = QLPreviewView(frame: window.contentLayoutRect, style: .normal) { preview.previewItem = url as NSURL; preview.autostarts = true; window.contentView = preview }
        window.center(); quickLookWindow?.close(); quickLookWindow = window; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    private func route(_ command: OrbitCommand, url: URL) {
        switch command {
        case .copyPath:
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url.path, forType: .string); NSPasteboard.general.setString("FileOrbit", forType: FileOrbitClipboard.marker); panel?.orderOut(nil)
        case .airDrop:
            guard let sharing = NSSharingService(named: .sendViaAirDrop), sharing.canPerform(withItems: [url]) else { model.errorMessage = "AirDrop is not available for this file on this Mac."; return }
            sharing.perform(withItems: [url]); panel?.orderOut(nil)
        case .terminal:
            guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { model.errorMessage = "Terminal could not be found."; return }
            NSWorkspace.shared.open([url.deletingLastPathComponent()], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
                Task { @MainActor in if let error { self?.model.errorMessage = error.localizedDescription } else { self?.panel?.orderOut(nil) } }
            }
        default: break
        }
    }
    @objc func openFileOrbitService(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        guard !urls.isEmpty else { error.pointee = "Select a file in Finder."; return }
        application(NSApp, open: urls)
    }

    private func showLoupeDemo() {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 420), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "FileOrbit · Local quality preview"; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: QualityPreviewStage())
        loupeDemoWindow?.close(); loupeDemoWindow = window; window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    private func showOnboarding() {
        if onboarding == nil {
            onboarding = OnboardingSandboxWindow(onSample: { [weak self] url, directory, dragging in
                guard let self, self.model.stage != .working else { return }
                self.model.select(url); self.model.outputDirectory = directory; self.model.isDraggingFile = dragging
                self.showPanel(nearPointer: false, activate: !dragging)
            }, onNotchDemo: { [weak self] in self?.commercial.notch.showDemo() }, onSettings: { [weak self] in self?.showSettings() })
        }
        onboarding?.show()
    }
    private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 550, height: 710), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "FileOrbit Settings"; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(model: model)); window.center(); settingsWindow = window
        }
        panel?.orderOut(nil); settingsWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func windowWillClose(_ notification: Notification) {
        if let closing = notification.object as? NSWindow, closing === redactionWindow { redactionEditor?.cancel() }
    }
    func applicationWillTerminate(_ notification: Notification) {
        commercial.stop()
        if let outsideClick { NSEvent.removeMonitor(outsideClick) }; if let panelKeyboard { NSEvent.removeMonitor(panelKeyboard) }
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }; dragMonitor.stop()
    }
}
@main struct FileOrbitApp {
    @MainActor static func main() {
        let app = NSApplication.shared, delegate = AppDelegate(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
