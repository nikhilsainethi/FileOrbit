import Foundation
import Combine

struct StudioActionDescriptor: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: String
}

@MainActor
final class StudioPreferences: ObservableObject {
    static let shared = StudioPreferences()
    private let defaults: UserDefaults
    @Published var appearance: String {
        didSet { defaults.set(appearance, forKey: "FileOrbit.appearance") }
    }
    @Published var rememberHistory: Bool {
        didSet { defaults.set(rememberHistory, forKey: "FileOrbit.rememberHistory") }
    }
    @Published private(set) var orders: [String: [String]]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = defaults.string(forKey: "FileOrbit.appearance") ?? "system"
        rememberHistory = defaults.bool(forKey: "FileOrbit.rememberHistory")
        orders = defaults.dictionary(forKey: "FileOrbit.radialOrders") as? [String: [String]] ?? [:]
    }

    func orderedIDs(_ availableIDs: [String], mode: String) -> [String] {
        var seen = Set<String>()
        let valid = Set(availableIDs)
        return ((orders[mode] ?? []) + availableIDs).filter { valid.contains($0) && seen.insert($0).inserted }
    }

    func setOrder(_ ids: [String], mode: String) {
        var seen = Set<String>()
        orders[mode] = ids.filter { seen.insert($0).inserted }
        defaults.set(orders, forKey: "FileOrbit.radialOrders")
    }

    func move(id: String, before target: String, availableIDs: [String], mode: String) {
        guard id != target, availableIDs.contains(id), availableIDs.contains(target) else { return }
        var ordered = orderedIDs(availableIDs, mode: mode)
        ordered.removeAll { $0 == id }
        guard let index = ordered.firstIndex(of: target) else { return }
        ordered.insert(id, at: index)
        setOrder(ordered, mode: mode)
    }

    func reset(mode: String) {
        orders.removeValue(forKey: mode)
        defaults.set(orders, forKey: "FileOrbit.radialOrders")
    }
}
