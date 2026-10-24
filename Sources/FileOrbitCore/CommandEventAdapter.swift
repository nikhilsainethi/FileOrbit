import Foundation

public struct CommandModifierState: OptionSet, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let command = CommandModifierState(rawValue: 1 << 0)
    public static let shift = CommandModifierState(rawValue: 1 << 1)
    public static let control = CommandModifierState(rawValue: 1 << 2)
    public static let option = CommandModifierState(rawValue: 1 << 3)
    public static let function = CommandModifierState(rawValue: 1 << 4)
    public static let capsLock = CommandModifierState(rawValue: 1 << 5)
}

public struct CommandEventAdapter: Sendable {
    private var commandWasDown = false
    private var pressedCommandKey: UInt16?
    public init() {}
    public mutating func reset() { commandWasDown = false; pressedCommandKey = nil }

    /// Receives only modifier-change key codes, never typed characters. The
    /// Command keys are macOS virtual codes 54 (right) and 55 (left). A latched
    /// Caps Lock state is harmless; pressing Caps Lock (or any other modifier)
    /// emits its own non-Command flagsChanged event and cancels the gesture.
    public mutating func flagsChanged(keyCode: UInt16, modifiers: CommandModifierState) -> CommandGestureEvent {
        let down = modifiers.contains(.command)
        let other: CommandModifierState = [.shift, .control, .option, .function]
        guard (keyCode == 54 || keyCode == 55), modifiers.intersection(other).isEmpty else {
            commandWasDown = down; pressedCommandKey = nil
            return .interference
        }
        if down && !commandWasDown {
            commandWasDown = true; pressedCommandKey = keyCode
            return .commandDown
        }
        if !down && commandWasDown && pressedCommandKey == keyCode {
            commandWasDown = false; pressedCommandKey = nil
            return .commandUp
        }
        // Overlapping left/right Command presses, mismatched releases and
        // duplicate flag events are ambiguous; require a fresh complete tap.
        commandWasDown = down
        pressedCommandKey = nil
        return .interference
    }
}
