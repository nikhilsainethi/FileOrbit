import Foundation

public enum CommandGestureEvent: Sendable { case commandDown, commandUp, interference }

/// A timestamp-driven recognizer independent of AppKit and system permissions.
/// A gesture consists of two complete press/release cycles, with no intervening
/// key, modifier, or mouse action. Interference must be supplied by the caller.
public struct DoubleCommandDetector: Sendable {
    private let maximumInterval: TimeInterval
    private let maximumHold: TimeInterval
    private var downAt: TimeInterval?
    private var firstReleaseAt: TimeInterval?
    private var lastTimestamp: TimeInterval?

    public init(maximumInterval: TimeInterval = 0.35, maximumHold: TimeInterval = 0.3) {
        self.maximumInterval = maximumInterval.isFinite && maximumInterval > 0 ? maximumInterval : 0.35
        self.maximumHold = maximumHold.isFinite && maximumHold > 0 ? maximumHold : 0.3
    }

    public mutating func reset() {
        downAt = nil
        firstReleaseAt = nil
        lastTimestamp = nil
    }

    public mutating func handle(_ event: CommandGestureEvent, at timestamp: TimeInterval) -> Bool {
        guard timestamp.isFinite, timestamp >= 0,
              lastTimestamp.map({ timestamp >= $0 }) ?? true else {
            reset()
            return false
        }
        lastTimestamp = timestamp
        switch event {
        case .interference:
            downAt = nil
            firstReleaseAt = nil
        case .commandDown:
            guard downAt == nil else {
                downAt = nil
                firstReleaseAt = nil
                return false
            }
            downAt = timestamp
        case .commandUp:
            guard let down = downAt else { return false }
            downAt = nil
            guard timestamp - down <= maximumHold else {
                firstReleaseAt = nil
                return false
            }
            if let firstRelease = firstReleaseAt, timestamp - firstRelease <= maximumInterval {
                firstReleaseAt = nil
                return true
            }
            firstReleaseAt = timestamp
        }
        return false
    }
}
