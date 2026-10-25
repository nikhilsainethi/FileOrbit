import Foundation
import CoreGraphics
import Combine

/// Display snapshots use AppKit's global bottom-left coordinate system.
struct PortalScreen: Equatable, Sendable {
    let frame: CGRect
    let safeTop: CGFloat
    let topLeft: CGRect?
    let topRight: CGRect?
}

struct NotchPortalLayout: Equatable, Sendable {
    let frame: CGRect
    let hasHardwareNotch: Bool
    let cutoutWidth: CGFloat
}

enum NotchPortalGeometry {
    static func layout(on screen: PortalScreen, expanded: Bool, shelfVisible: Bool) -> NotchPortalLayout {
        let screenFrame = screen.frame
        let safeTop = min(max(0, screen.safeTop.isFinite ? screen.safeTop : 0), max(0, screenFrame.height - 28))
        var center = screenFrame.midX
        var cutoutWidth: CGFloat = 0
        if safeTop > 0, let left = screen.topLeft, let right = screen.topRight,
           !left.isEmpty, !right.isEmpty,
           left.minX >= screenFrame.minX, right.maxX <= screenFrame.maxX,
           left.maxX < right.minX, left.maxY <= screenFrame.maxY + 1,
           right.maxY <= screenFrame.maxY + 1 {
            center = (left.maxX + right.minX) / 2
            cutoutWidth = right.minX - left.maxX
        }
        let desiredWidth: CGFloat = expanded ? 340 : (cutoutWidth > 0 ? max(180, min(300, cutoutWidth + 16)) : 180)
        let width = min(desiredWidth, max(1, screenFrame.width - 12))
        let height = min(expanded ? (shelfVisible ? 266 : 96) : 28, max(1, screenFrame.height - safeTop))
        let x = min(max(center - width / 2, screenFrame.minX + 6), screenFrame.maxX - width - 6)
        return NotchPortalLayout(frame: CGRect(x: x, y: screenFrame.maxY - safeTop - height, width: width, height: height),
                                 hasHardwareNotch: cutoutWidth > 0, cutoutWidth: cutoutWidth)
    }
}

/// Main-actor pasteboard access feeds this value-only guard. No snapshot can commit
/// after another application has changed the clipboard in the meantime.
struct ClipboardRevisionGate: Sendable {
    private var lastObserved: Int
    private var ownWrite: Int?
    init(initial: Int) { lastObserved = initial }
    mutating func observe(_ revision: Int) -> Bool {
        guard revision != lastObserved else { return false }
        lastObserved = revision
        if revision == ownWrite { ownWrite = nil; return false }
        ownWrite = nil
        return true
    }
    mutating func didWrite(_ revision: Int) { ownWrite = revision; lastObserved = revision }
    func canCommit(expected: Int, current: Int) -> Bool { expected == current }
}

/// Uptime, not wall-clock dates, keeps expiry stable across clock adjustments.
struct OrbLifetime: Sendable {
    static let duration: TimeInterval = 4.5
    private var startedAt: TimeInterval
    private var pausedAt: TimeInterval?
    private var pausedDuration: TimeInterval = 0
    init(startedAt: TimeInterval) { self.startedAt = startedAt }
    func remaining(at time: TimeInterval) -> TimeInterval {
        let elapsed = max(0, (pausedAt ?? time) - startedAt - pausedDuration)
        return max(0, Self.duration - elapsed)
    }
    func isExpired(at time: TimeInterval) -> Bool { remaining(at: time) <= 0 }
    mutating func setPaused(_ paused: Bool, at time: TimeInterval) {
        if paused, pausedAt == nil { pausedAt = time }
        else if !paused, let pausedAt { pausedDuration += max(0, time - pausedAt); self.pausedAt = nil }
    }
}

struct ScreenshotObservationGate: Sendable {
    private struct Signature: Equatable, Sendable { let bytes: Int; let modified: TimeInterval }
    private let startedAt: Date
    private var pending: [URL: Signature] = [:]
    private var delivered: [URL: Date] = [:]
    private var deliveredFloor: Date?
    init(startedAt: Date) { self.startedAt = startedAt }
    mutating func observe(url: URL, created: Date, bytes: Int, modified: TimeInterval) -> Bool {
        guard created >= startedAt, bytes > 0, bytes <= ClipboardSnapshot.maximumBytes, delivered[url] == nil, deliveredFloor.map({ created > $0 }) ?? true else { return false }
        let signature = Signature(bytes: bytes, modified: modified)
        if pending[url] == signature {
            pending.removeValue(forKey: url); delivered[url] = created
            // Bound history without ever replaying evicted screenshot records.
            if delivered.count > 512 {
                let oldest = delivered.sorted { $0.value < $1.value }.prefix(256)
                deliveredFloor = oldest.map(\.value).max()
                for entry in oldest { delivered.removeValue(forKey: entry.key) }
            }
            return true
        }
        if pending.count >= 64, pending[url] == nil,
           let oldest = pending.min(by: { $0.value.modified < $1.value.modified })?.key {
            pending.removeValue(forKey: oldest)
        }
        pending[url] = signature
        return false
    }
}

@MainActor
final class SpatialPreferences: ObservableObject {
    static let shared = SpatialPreferences()
    private let defaults: UserDefaults
    @Published var notchEnabled: Bool { didSet { defaults.set(notchEnabled, forKey: "FileOrbit.notchEnabled") } }
    @Published var clipboardEnabled: Bool { didSet { defaults.set(clipboardEnabled, forKey: "FileOrbit.clipboardEnabled") } }
    @Published var screenshotEnabled: Bool { didSet { defaults.set(screenshotEnabled, forKey: "FileOrbit.screenshotEnabled") } }
    @Published var favoritePipelineID: String { didSet { defaults.set(favoritePipelineID, forKey: "FileOrbit.favoritePipelineID") } }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        notchEnabled = defaults.bool(forKey: "FileOrbit.notchEnabled")
        clipboardEnabled = defaults.bool(forKey: "FileOrbit.clipboardEnabled")
        screenshotEnabled = defaults.bool(forKey: "FileOrbit.screenshotEnabled")
        favoritePipelineID = defaults.string(forKey: "FileOrbit.favoritePipelineID") ?? "optimize-webp-copy"
    }
}
