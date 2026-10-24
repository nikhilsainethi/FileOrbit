import AppKit

struct FinderDragSession {
    private var baseline: Int?
    private var current: Int?
    mutating func mouseDown(pasteboardChange: Int) { baseline = pasteboardChange; current = nil }
    mutating func observeDrag(pasteboardChange: Int) -> Bool {
        guard let baseline, pasteboardChange != baseline else { return false }
        current = pasteboardChange; return true
    }
    func isCurrent(pasteboardChange: Int) -> Bool { current == pasteboardChange }
    mutating func end() { baseline = nil; current = nil }
}
/// Observes only file drags and modifier changes. It never consumes keystrokes,
/// changes the clipboard, or takes focus from the source of a drag.
@MainActor final class FinderDragMonitor {
    private var monitor: Any?
    private var session = FinderDragSession()
    private var revealed = false
    var onReveal: (([URL], OrbitMode) -> Void)?
    var onMode: ((OrbitMode) -> Void)?
    var onEnd: (() -> Void)?
    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .flagsChanged, .leftMouseUp]) { [weak self] event in
            guard let self else { return }
            let pasteboard = NSPasteboard(name: .drag)
            if event.type == .leftMouseDown {
                self.session.mouseDown(pasteboardChange: pasteboard.changeCount); self.revealed = false; return
            }
            if event.type == .leftMouseUp {
                if self.revealed { self.onEnd?() }; self.session.end(); self.revealed = false; return
            }
            guard NSEvent.pressedMouseButtons & 1 != 0,
                  NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else { return }
            if event.type == .leftMouseDragged { _ = self.session.observeDrag(pasteboardChange: pasteboard.changeCount) }
            guard self.session.isCurrent(pasteboardChange: pasteboard.changeCount),
                  let mode = OrbitMode.fromModifiers(event.modifierFlags) else { return }
            let urls = OrbitDropSession.pasteboardURLs()
            guard !urls.isEmpty else { return }
            if !self.revealed { self.revealed = true; self.onReveal?(urls, mode) }
            else { self.onMode?(mode) }
        }
    }
    func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil; session.end(); revealed = false }
}
