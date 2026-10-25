import Testing
import AppKit
@testable import FileOrbit

@Suite @MainActor struct ModifierPreferencesTests {
    @Test func defaultChordsAndCommandGuardPreserveFinderBehavior() {
        let name = "fileorbit-modifiers-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = ModifierPreferences(defaults: defaults)
        #expect(preferences.mode(for: .shift) == .convert)
        #expect(preferences.mode(for: .option) == .modify)
        #expect(preferences.mode(for: .control) == .quickActions)
        #expect(preferences.mode(for: [.command, .shift]) == nil)
    }
    @Test func collisionsSwapAndPersistWithoutDuplicateTriggers() {
        let name = "fileorbit-modifiers-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = ModifierPreferences(defaults: defaults)
        preferences.set(trigger: .option, for: .convert)
        #expect(preferences.trigger(for: .convert) == .option)
        #expect(preferences.trigger(for: .modify) == .shift)
        preferences.set(trigger: .function, for: .quickActions)
        let reloaded = ModifierPreferences(defaults: defaults)
        #expect(reloaded.mode(for: .function) == .quickActions)
        #expect(Set(OrbitMode.allCases.map { reloaded.trigger(for: $0) }).count == 3)
        #expect(reloaded.key(for: .quickActions) == "fn")
    }
    @Test func corruptPersistedValuesRecoverUniqueUsableMappings() {
        let name = "fileorbit-modifiers-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(["convert": "control", "modify": "invalid", "quickActions": "control"], forKey: "FileOrbit.modifierTriggers")
        let preferences = ModifierPreferences(defaults: defaults)
        #expect(Set(OrbitMode.allCases.map { preferences.trigger(for: $0) }).count == 3)
        #expect(preferences.trigger(for: .convert) == .control)
    }
}
