import AppKit
import Combine

/// Command is deliberately not assignable: double-tap Command and normal shortcuts retain
/// their established behavior. These are only the three Finder-drag mode selectors.
enum ModifierTrigger: String, CaseIterable, Identifiable, Sendable {
    case shift, option, control, function
    var id: String { rawValue }
    var title: String { switch self { case .shift: return "Shift"; case .option: return "Option"; case .control: return "Control"; case .function: return "Fn" } }
    var symbol: String { switch self { case .shift: return "⇧"; case .option: return "⌥"; case .control: return "⌃"; case .function: return "fn" } }
    var flag: NSEvent.ModifierFlags { switch self { case .shift: return .shift; case .option: return .option; case .control: return .control; case .function: return .function } }
}

@MainActor final class ModifierPreferences: ObservableObject {
    static let shared = ModifierPreferences()
    @Published private(set) var mappings: [String: String]
    private let defaults: UserDefaults
    private static let key = "FileOrbit.modifierTriggers"
    private static let defaultValues: [String: ModifierTrigger] = ["convert": .shift, "modify": .option, "quickActions": .control]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
        var used = Set<ModifierTrigger>(), recovered: [String: String] = [:]
        for mode in OrbitMode.allCases {
            let requested = stored[mode.rawValue].flatMap(ModifierTrigger.init(rawValue:))
            let fallback = Self.defaultValues[mode.rawValue] ?? .shift
            let selected = [requested, fallback].compactMap { $0 }.first { !used.contains($0) }
                ?? ModifierTrigger.allCases.first { !used.contains($0) } ?? .shift
            recovered[mode.rawValue] = selected.rawValue; used.insert(selected)
        }
        mappings = recovered
    }
    func trigger(for mode: OrbitMode) -> ModifierTrigger {
        mappings[mode.rawValue].flatMap(ModifierTrigger.init(rawValue:)) ?? Self.defaultValues[mode.rawValue] ?? .shift
    }
    func key(for mode: OrbitMode) -> String { trigger(for: mode).symbol }
    func mode(for flags: NSEvent.ModifierFlags) -> OrbitMode? {
        guard !flags.contains(.command) else { return nil }
        // Preserve the original precedence for overlapping physical modifiers.
        for trigger in [ModifierTrigger.control, .option, .shift, .function] where flags.contains(trigger.flag) {
            if let mode = OrbitMode.allCases.first(where: { self.trigger(for: $0) == trigger }) { return mode }
        }
        return nil
    }
    func set(trigger: ModifierTrigger, for mode: OrbitMode) {
        let prior = self.trigger(for: mode)
        guard prior != trigger else { return }
        var next = mappings
        if let other = OrbitMode.allCases.first(where: { $0 != mode && self.trigger(for: $0) == trigger }) {
            next[other.rawValue] = prior.rawValue
        }
        next[mode.rawValue] = trigger.rawValue; mappings = next
        defaults.set(next, forKey: Self.key)
    }
    func reset() {
        mappings = Self.defaultValues.mapValues(\.rawValue)
        defaults.set(mappings, forKey: Self.key)
    }
}
