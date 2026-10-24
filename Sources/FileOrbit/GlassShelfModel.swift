import AppKit
import Combine
import FileOrbitCore

@MainActor
final class GlassShelfModel: ObservableObject {
    enum Mode: String, CaseIterable { case convert, compress }
    enum ItemState: Equatable {
        case waiting, running, complete, failed(String), cancelled
        var label: String {
            switch self {
            case .waiting: return "Ready"
            case .running: return "Processing…"
            case .complete: return "Saved"
            case .failed(let message): return message
            case .cancelled: return "Cancelled"
            }
        }
    }
    struct Item: Identifiable {
        let id = UUID()
        let url: URL
        var state: ItemState = .waiting
        var result: ConversionResult?
    }
    @Published private(set) var items: [Item] = []
    @Published var mode: Mode = .convert
    @Published var selectedFormat: OutputFormat = .pdf
    @Published var preset: CompressionPreset = .balanced
    @Published var isPinned = false
    @Published private(set) var isRunning = false
    @Published private(set) var isCancelling = false
    @Published private(set) var completedCount = 0
    @Published private(set) var totalCount = 0
    @Published private(set) var inputError: String?
    var environment: EngineEnvironment
    var onCompleted: ((URL, ConversionResult) -> Void)?
    var onFinished: (() -> Void)?
    private var cancellation: CancellationToken?

    init(environment: EngineEnvironment = .discover()) { self.environment = environment }

    var availableFormats: [OutputFormat] {
        guard let first = items.first else { return [] }
        func formats(_ url: URL) -> [OutputFormat] {
            CapabilityCatalog.actions(for: url, environment: environment).compactMap {
                if case .convert(let format) = $0.operation { return format }
                return nil
            }
        }
        return formats(first.url).filter { format in items.dropFirst().allSatisfy { formats($0.url).contains(format) } }
    }
    var canCompressAll: Bool {
        !items.isEmpty && items.allSatisfy { item in
            CapabilityCatalog.actions(for: item.url, environment: environment).contains {
                if case .compress = $0.operation { return true }
                return false
            }
        }
    }
    var canRun: Bool { !isRunning && !items.isEmpty && (mode == .compress ? canCompressAll : availableFormats.contains(selectedFormat)) }
    var progress: Double { totalCount > 0 ? Double(completedCount) / Double(totalCount) : 0 }
    var completedResults: [ConversionResult] { items.compactMap(\.result) }

    func add(_ urls: [URL]) {
        guard !isRunning else { return }
        inputError = nil
        var known = Set(items.map { $0.url.resolvingSymlinksInPath().standardizedFileURL.path })
        var rejected = 0
        for url in urls {
            guard url.isFileURL,
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  FileKind.detect(url) != .unsupported else { rejected += 1; continue }
            if known.insert(url.resolvingSymlinksInPath().standardizedFileURL.path).inserted { items.append(Item(url: url)) }
        }
        if rejected > 0 { inputError = "\(rejected) unsupported item\(rejected == 1 ? " was" : "s were") skipped." }
        reconcileSelection()
    }

    func remove(_ id: UUID) {
        guard !isRunning else { return }
        items.removeAll { $0.id == id }
        reconcileSelection()
    }

    func clear() {
        guard !isRunning else { return }
        items = []; totalCount = 0; completedCount = 0; inputError = nil
    }

    private func reconcileSelection() {
        let formats = availableFormats
        if !formats.contains(selectedFormat), let first = formats.first { selectedFormat = first }
    }

    func run() {
        guard canRun else { return }
        let operation: FileOperation = mode == .compress ? .compress(preset) : .convert(selectedFormat)
        let batch = items.map { ($0.id, $0.url) }
        let engine = ConversionEngine(environment: environment)
        let token = CancellationToken()
        cancellation = token
        isRunning = true; isCancelling = false; completedCount = 0; totalCount = batch.count
        for index in items.indices { items[index].state = .waiting; items[index].result = nil }
        Task { [weak self] in
            for (id, url) in batch {
                guard let self else { return }
                if token.isCancelled {
                    self.update(id, state: .cancelled)
                    continue
                }
                self.update(id, state: .running)
                let outcome = await Task.detached(priority: .userInitiated) {
                    Result { try engine.run(ConversionRequest(input: url, operation: operation), cancellation: token) }
                }.value
                switch outcome {
                case .success(let result):
                    self.update(id, state: .complete, result: result)
                    self.onCompleted?(url, result)
                case .failure(let error):
                    self.update(id, state: token.isCancelled ? .cancelled : .failed(error.localizedDescription))
                }
                self.completedCount += 1
            }
            guard let self else { return }
            self.isRunning = false; self.isCancelling = false; self.cancellation = nil
            self.onFinished?()
        }
    }

    func cancel() { guard isRunning else { return }; isCancelling = true; cancellation?.cancel() }

    private func update(_ id: UUID, state: ItemState, result: ConversionResult? = nil) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].state = state; items[index].result = result
    }
}
