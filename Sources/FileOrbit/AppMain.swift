import AppKit
import SwiftUI
import FileOrbitCore

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
    private var activationObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(CommandLine.arguments.contains("--ui-test") ? .regular : .accessory)
        createStatusItem()
        model.onSettings = { [weak self] in self?.showSettings() }
        model.onDismiss = { [weak self] in self?.panel?.orderOut(nil) }
        monitor.onGesture = { [weak self] in self?.handleFinderGesture() }
        monitor.start()
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.monitor.reset()
                self?.model.refresh()
                self?.monitor.start()
            }
        }
        outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.model.stage != .working else { return }
            self.panel?.orderOut(nil)
        }
        if let index = CommandLine.arguments.firstIndex(of: "--open"), CommandLine.arguments.indices.contains(index + 1) {
            model.select(URL(fileURLWithPath: CommandLine.arguments[index + 1])); showPanel(nearPointer: false)
        } else if !UserDefaults.standard.bool(forKey: "FileOrbit.hasLaunched") {
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
        menu.addItem(withTitle: "Open FileOrbit", action: #selector(openPanel), keyEquivalent: "")
        menu.addItem(withTitle: "Choose File…", action: #selector(chooseFile), keyEquivalent: "o")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(settings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit FileOrbit", action: #selector(quit), keyEquivalent: "q")
        for entry in menu.items { entry.target = self }
        item.menu = menu; statusItem = item
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
            let created = OrbitPanel(contentRect: NSRect(x: 0, y: 0, width: 528, height: 668), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            created.contentView = NSHostingView(rootView: OrbitView(model: model))
            created.isOpaque = false; created.backgroundColor = .clear; created.hasShadow = true
            created.level = .floating; created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            created.isReleasedWhenClosed = false; created.hidesOnDeactivate = false
            created.isMovableByWindowBackground = false
            created.title = "FileOrbit"
            panel = created
        }
        guard let panel else { return }
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var origin = CGPoint(x: visible.midX - panel.frame.width / 2, y: visible.midY - panel.frame.height / 2)
        if nearPointer { origin = CGPoint(x: pointer.x - panel.frame.width / 2, y: pointer.y - panel.frame.height / 2) }
        origin.x = min(max(origin.x, visible.minX + 12), visible.maxX - panel.frame.width - 12)
        origin.y = min(max(origin.y, visible.minY + 12), visible.maxY - panel.frame.height - 12)
        panel.setFrameOrigin(origin)
        panel.makeKeyAndOrderFront(nil)
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
