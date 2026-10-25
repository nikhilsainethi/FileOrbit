import Foundation
import Combine

enum ImpactCategory: String, CaseIterable, Codable, Identifiable {
    case conversion, compression, isolation, redaction
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// Aggregate counters contain no paths, file names, text or image payloads.
@MainActor final class ImpactStore: ObservableObject {
    static let shared = ImpactStore()
    struct Record: Codable { let id: UUID; let day: String; let category: ImpactCategory; let avoided: Int64 }
    struct State: Codable {
        var operations: [String: Int64] = [:]
        var avoided: Int64 = 0
        var daily: [String: Int64] = [:]
        var recent: [Record] = []
    }
    @Published private(set) var state = State()
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "FileOrbit.impact.v1"), data.count < 1_000_000,
           let saved = try? JSONDecoder().decode(State.self, from: data), Self.valid(saved) {
            state = saved
        }
    }
    var totalOperations: Int64 { state.operations.values.reduce(0, +) }
    var avoidedBytes: Int64 { state.avoided }
    var estimatedSeconds: Int64 { totalOperations * 20 }
    var sparkline: [Double] {
        let calendar = Calendar(identifier: .gregorian)
        return (0..<14).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
            return Double(state.daily[Self.day(date), default: 0])
        }
    }
    func record(id: UUID, category: ImpactCategory, inputBytes: Int64, outputBytes: Int64, date: Date = Date()) {
        guard inputBytes >= 0, outputBytes >= 0, inputBytes <= 1_073_741_824,
              !state.recent.contains(where: { $0.id == id }), totalOperations < 1_000_000_000 else { return }
        let avoided = max(0, inputBytes - outputBytes), day = Self.day(date)
        state.operations[category.rawValue, default: 0] += 1
        state.avoided = min(1_073_741_824_000_000_000, state.avoided + avoided)
        state.daily[day] = min(1_073_741_824_000_000_000, state.daily[day, default: 0] + avoided)
        state.recent.insert(Record(id: id, day: day, category: category, avoided: avoided), at: 0)
        state.recent = Array(state.recent.prefix(1000))
        for key in state.daily.keys.sorted().dropLast(90) { state.daily.removeValue(forKey: key) }
        save()
    }
    func undo(id: UUID) {
        guard let record = state.recent.first(where: { $0.id == id }) else { return }
        state.operations[record.category.rawValue] = max(0, state.operations[record.category.rawValue, default: 0] - 1)
        state.avoided = max(0, state.avoided - record.avoided)
        if state.daily[record.day] != nil { state.daily[record.day] = max(0, state.daily[record.day, default: 0] - record.avoided) }
        state.recent.removeAll { $0.id == id }; save()
    }
    func clear() { state = State(); defaults.removeObject(forKey: "FileOrbit.impact.v1") }
    private static func valid(_ value: State) -> Bool {
        let maximum: Int64 = 1_073_741_824_000_000_000
        let categories = Set(ImpactCategory.allCases.map(\.rawValue))
        guard value.operations.count <= categories.count,
              value.operations.keys.allSatisfy(categories.contains),
              value.operations.values.allSatisfy({ (0...1_000_000_000).contains($0) }),
              value.operations.values.reduce(0, +) <= 1_000_000_000,
              (0...maximum).contains(value.avoided), value.daily.count <= 90,
              value.daily.values.allSatisfy({ (0...maximum).contains($0) }),
              value.recent.count <= 1000, Set(value.recent.map(\.id)).count == value.recent.count,
              value.recent.allSatisfy({ (0...1_073_741_824).contains($0.avoided) }) else { return false }
        return true
    }
    private func save() { defaults.set(try? JSONEncoder().encode(state), forKey: "FileOrbit.impact.v1") }
    private static func day(_ date: Date) -> String { String(date.ISO8601Format().prefix(10)) }
}
