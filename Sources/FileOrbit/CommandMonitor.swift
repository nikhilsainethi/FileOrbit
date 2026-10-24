import AppKit
import FileOrbitCore
import OSLog

enum ShortcutDiagnostics {
    private static let logger = Logger(subsystem: "io.fileorbit.mac", category: "Shortcut")
    static func record(_ message: String) {
        guard UserDefaults.standard.bool(forKey: "FileOrbit.shortcutDiagnostics") else { return }
        logger.notice("\(message, privacy: .public)")
    }
}

@MainActor
final class CommandMonitor {
    private var global: Any?
    private var local: Any?
    private var detector = DoubleCommandDetector()
    private var adapter = CommandEventAdapter()
    var onGesture: (() -> Void)?
    func start() {
        let trusted = AXIsProcessTrusted()
        ShortcutDiagnostics.record("start trusted=\(trusted) global=\(global != nil) local=\(local != nil)")
        guard global == nil, trusted else { return }
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in self?.receive(event) }
        local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in self?.receive(event); return event }
        ShortcutDiagnostics.record("registered global=\(global != nil) local=\(local != nil)")
    }
    func reset() { detector.reset(); adapter.reset() }
    private func receive(_ event: NSEvent) {
        // Observe only modifier state and interference, never retain typed characters.
        let finderActive = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
        if event.type == .flagsChanged {
            ShortcutDiagnostics.record("modifier code=\(event.keyCode) flags=\(event.modifierFlags.rawValue) time=\(event.timestamp) finder=\(finderActive)")
        }
        guard finderActive else { reset(); return }
        guard event.type == .flagsChanged else {
            _ = detector.handle(.interference, at: event.timestamp)
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: CommandModifierState = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.function) { modifiers.insert(.function) }
        if flags.contains(.capsLock) { modifiers.insert(.capsLock) }
        let gestureEvent = adapter.flagsChanged(keyCode: event.keyCode, modifiers: modifiers)
        let recognized = detector.handle(gestureEvent, at: event.timestamp)
        ShortcutDiagnostics.record("gesture event=\(gestureEvent) recognized=\(recognized)")
        if recognized { onGesture?() }
    }
    deinit {
        if let global { NSEvent.removeMonitor(global) }
        if let local { NSEvent.removeMonitor(local) }
    }
}
