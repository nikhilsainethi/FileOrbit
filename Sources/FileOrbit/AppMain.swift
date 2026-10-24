import AppKit
import SwiftUI
import FileOrbitCore
import OSLog

enum FileOrbitRuntime {
    static var isPreview: Bool { Bundle.main.object(forInfoDictionaryKey: "FileOrbitPreview") as? Bool == true }
    private static let previewLogger = Logger(subsystem: "io.fileorbit.preview", category: "Panel")
    static func recordPreview(_ event: String) {
        if isPreview { previewLogger.notice("\(event, privacy: .public)") }
    }
    static var displayName: String { isPreview ? "FileOrbit Preview" : "FileOrbit" }
}

enum OrbitPanelPlacement {
    static func origin(size: CGSize, visibleFrame: CGRect, anchor: CGPoint?) -> CGPoint {
        let center = anchor ?? CGPoint(x: visibleFrame.midX, y: visibleFrame.midY)
        func clamp(_ desired: CGFloat, minimum: CGFloat, maximum: CGFloat, extent: CGFloat) -> CGFloat {
            // Keep the window's origin visible even on a display smaller than the panel.
            guard maximum - minimum >= extent + 24 else { return minimum }
            return min(max(desired, minimum + 12), maximum - extent - 12)
        }
        return CGPoint(
            x: clamp(center.x - size.width / 2, minimum: visibleFrame.minX, maximum: visibleFrame.maxX, extent: size.width),
            y: clamp(center.y - size.height / 2, minimum: visibleFrame.minY, maximum: visibleFrame.maxY, extent: size.height)
        )
    }
}

final class OrbitPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = AppModel()
    private let monitor = CommandMonitor()
    private var statusItem: NSStatusItem?
    private var panel: OrbitPanel?
    private var settingsWindow: NSWindow?
    private var outsideClick: Any?
    private var panelKeyboard: Any?
    private var activationObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(FileOrbitRuntime.isPreview || CommandLine.arguments.contains("--ui-test") ? .regular : .accessory)
        createStatusItem()
        model.onSettings = { [weak self] in self?.showSettings() }
        model.onDismiss = { [weak self] in self?.panel?.orderOut(nil); FileOrbitRuntime.recordPreview("Dismissed with close action") }
        monitor.onGesture = { [weak self] in self?.handleFinderGesture() }
        if !FileOrbitRuntime.isPreview { monitor.start() }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.monitor.reset()
                self?.model.refresh()
                if !FileOrbitRuntime.isPreview { self?.monitor.start() }
            }
        }
        outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.model.stage != .working, !FileOrbitRuntime.isPreview else { return }
            self.panel?.orderOut(nil)
            FileOrbitRuntime.recordPreview("Outside click dismissed idle panel")
        }
        // Own-window events do not require Accessibility permission. Keep Escape
        // reliable after a stage transition even when no SwiftUI control is focused.
        panelKeyboard = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.panel, (event.window === panel || (event.window == nil && panel.isKeyWindow)), event.keyCode == 53,
                  event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return event }
            if self.model.stage == .compression { self.model.back() }
            else if self.model.stage != .working { panel.orderOut(nil) }
            FileOrbitRuntime.recordPreview("Escape handled for panel")
            return nil
        }
        if let index = CommandLine.arguments.firstIndex(of: "--open"), CommandLine.arguments.indices.contains(index + 1) {
            model.select(URL(fileURLWithPath: CommandLine.arguments[index + 1])); showPanel(nearPointer: false)
        } else if FileOrbitRuntime.isPreview || !UserDefaults.standard.bool(forKey: "FileOrbit.hasLaunched") {
            UserDefaults.standard.set(true, forKey: "FileOrbit.hasLaunched")
            showPanel(nearPointer: false)
        }
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.count == 1 else { model.selectionFailed("Open one file at a time in FileOrbit."); showPanel(nearPointer: false); return }
        model.select(urls[0]); showPanel(nearPointer: false)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel(nearPointer: false)
        return true
    }
    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let symbol = NSImage(systemSymbolName: "circle.hexagongrid", accessibilityDescription: "FileOrbit")
        symbol?.isTemplate = true
        item.button?.image = symbol
        let menu = NSMenu()
        if FileOrbitRuntime.isPreview {
            let notice = NSMenuItem(title: "Design preview · shortcut stays with FileOrbit", action: nil, keyEquivalent: "")
            notice.isEnabled = false
            menu.addItem(notice)
            menu.addItem(.separator())
            let appearance = NSMenuItem(title: "Preview appearance", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for (name, tag) in [("System", 0), ("Light", 1), ("Dark", 2)] {
                let entry = NSMenuItem(title: name, action: #selector(previewAppearance(_:)), keyEquivalent: "")
                entry.tag = tag; entry.target = self; submenu.addItem(entry)
            }
            appearance.submenu = submenu; menu.addItem(appearance)
        }
        menu.addItem(withTitle: "Open \(FileOrbitRuntime.displayName)", action: #selector(openPanel), keyEquivalent: "")
        menu.addItem(withTitle: "Choose File…", action: #selector(chooseFile), keyEquivalent: "o")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(settings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit \(FileOrbitRuntime.displayName)", action: #selector(quit), keyEquivalent: "q")
        for entry in menu.items { entry.target = self }
        item.menu = menu; statusItem = item
        if FileOrbitRuntime.isPreview {
            let mainMenu = NSMenu()
            let application = NSMenuItem(title: FileOrbitRuntime.displayName, action: nil, keyEquivalent: "")
            application.submenu = menu.copy() as? NSMenu
            mainMenu.addItem(application)
            NSApp.mainMenu = mainMenu
        }
    }
    @objc private func previewAppearance(_ sender: NSMenuItem) {
        guard FileOrbitRuntime.isPreview else { return }
        NSApp.appearance = sender.tag == 1 ? NSAppearance(named: .aqua) : sender.tag == 2 ? NSAppearance(named: .darkAqua) : nil
        showPanel(nearPointer: false)
    }
    @objc private func openPanel() { model.refresh(); showPanel(nearPointer: false) }
    @objc private func chooseFile() { showPanel(nearPointer: false); model.chooseFile() }
    @objc private func settings() { showSettings() }
    @objc private func quit() {
        if model.stage == .working {
            let alert = NSAlert(); alert.messageText = "A file is still processing"
            alert.informativeText = "Cancel the operation in FileOrbit before quitting."
            alert.addButton(withTitle: "Return to FileOrbit"); alert.runModal(); showPanel(nearPointer: false)
        } else { NSApp.terminate(nil) }
    }
    private func handleFinderGesture() {
        ShortcutDiagnostics.record("handling Finder gesture")
        guard model.stage != .working else { showPanel(nearPointer: true); return }
        do { model.select(try FinderSelection.selectedFile()) }
        catch { model.selectionFailed(error.localizedDescription) }
        showPanel(nearPointer: true)
    }
    private func showPanel(nearPointer: Bool) {
        if panel == nil {
            let created = OrbitPanel(contentRect: NSRect(x: 0, y: 0, width: OrbitLayout.canvasSize.width, height: OrbitLayout.canvasSize.height), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            let hosting = NSHostingView(rootView: OrbitView(model: model))
            hosting.sizingOptions = []
            hosting.safeAreaRegions = []
            created.contentView = hosting
            created.isOpaque = false; created.backgroundColor = .clear; created.hasShadow = false
            created.level = .floating; created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            created.isReleasedWhenClosed = false; created.hidesOnDeactivate = false
            created.isMovableByWindowBackground = false
            created.title = FileOrbitRuntime.displayName
            panel = created
        }
        guard let panel else { return }
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = OrbitPanelPlacement.origin(size: panel.frame.size, visibleFrame: visible, anchor: nearPointer ? pointer : nil)
        panel.setFrameOrigin(origin)
        panel.makeKeyAndOrderFront(nil)
        FileOrbitRuntime.recordPreview("Panel shown")
        NSApp.activate(ignoringOtherApps: true)
    }
    private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 550, height: 710), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "FileOrbit Settings"; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            window.center(); settingsWindow = window
        }
        panel?.orderOut(nil)
        settingsWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func applicationWillTerminate(_ notification: Notification) {
        if let outsideClick { NSEvent.removeMonitor(outsideClick) }
        if let panelKeyboard { NSEvent.removeMonitor(panelKeyboard) }
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
    }
}

@main
struct FileOrbitApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
