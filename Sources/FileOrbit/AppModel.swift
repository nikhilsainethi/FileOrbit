import AppKit
import SwiftUI
import FileOrbitCore
import Combine

@MainActor
final class AppModel: ObservableObject {
    enum Stage: Hashable { case ready, compression, working, result }
    @Published var input: URL?
    @Published var actions: [FileAction] = []
    @Published var stage: Stage = .ready
    @Published var errorMessage: String?
    @Published var result: ConversionResult?
    @Published var preset: CompressionPreset = .balanced
    @Published var cancelling = false
    @Published var environment = EngineEnvironment.discover()
    @Published var accessibilityGranted = AXIsProcessTrusted()
    @Published var mode: OrbitMode = .convert { didSet { if oldValue != mode { resetInteraction() } } }
    @Published var selectedActionID: String?
    @Published var parameterParentID: String?
    @Published var selectedParameterID: String?
    @Published var isDraggingFile = false
    let inspector = FileInspector()
    let preferences = StudioPreferences.shared
    private var cancellation: CancellationToken?
    private var hoverTask: Task<Void, Never>?
    private var hoverTargetID: String?
    private var hoverStarted: ContinuousClock.Instant?
    private var pendingActivationID: String?
    private var subscriptions = Set<AnyCancellable>()

    init() {
        inspector.$metadataLoaded.dropFirst().sink { [weak self] ready in
            guard ready else { return }
            // Published sends before assignment; execute once the snapshot is installed.
            Task { @MainActor [weak self] in
                guard let self, self.inspector.metadataLoaded else { return }
                if let id = self.pendingActivationID, let action = self.orbitActions.first(where: { $0.id == id }) {
                    self.pendingActivationID = nil; self.activate(action)
                } else if let started = self.hoverStarted, started.duration(to: .now) >= .milliseconds(160), let id = self.hoverTargetID, let action = self.orbitActions.first(where: { $0.id == id }) {
                    self.openParameters(action)
                }
                self.objectWillChange.send()
            }
        }.store(in: &subscriptions)
    }
    var onSettings: (() -> Void)?
    var onDismiss: (() -> Void)?
    var onShelf: (([URL]) -> Void)?
    var onRoute: ((OrbitCommand, URL) -> Void)?
    var onRedact: ((URL) -> Void)?
    var onRunStarted: ((URL) -> Void)?
    var onRunCompleted: ((URL, ConversionResult) -> Void)?
    var onRunFailed: ((Error) -> Void)?

    var inputSize: String { inspector.sizeText }
    var dependencyHint: String? { input.flatMap { CapabilityCatalog.unavailableReason(for: $0, environment: environment) } }
    static func bytes(_ count: Int64) -> String { ByteCountFormatter.string(fromByteCount: count, countStyle: .file) }
    var orbitActions: [OrbitAction] { orbitActions(for: mode) }
    func orbitActions(for targetMode: OrbitMode) -> [OrbitAction] {
        guard let input else { return [] }
        let available: [OrbitAction]
        switch targetMode {
        case .convert:
            available = (actions.filter { if case .compress = $0.operation { return false }; return true }
                         + actions.filter { if case .compress = $0.operation { return true }; return false }).map(OrbitAction.init)
        case .modify:
            available = CapabilityCatalog.modificationActions(for: input, environment: environment).map(OrbitAction.init)
        case .quickActions:
            available = [
                .init(id: "shelf", title: "Shelf", symbol: "tray.2", subtitle: "Collect files for a batch", command: .shelf),
                .init(id: "airdrop", title: "AirDrop", symbol: "airplayaudio", subtitle: "Choose a nearby recipient", command: .airDrop),
                .init(id: "copy-path", title: "Copy Path", symbol: "link", subtitle: "Copy the file’s full path", command: .copyPath),
                .init(id: "terminal", title: "Terminal", symbol: "terminal", subtitle: "Open the containing folder", command: .terminal)
            ]
        }
        let lookup = Dictionary(uniqueKeysWithValues: available.map { ($0.id, $0) })
        return preferences.orderedIDs(available.map(\.id), mode: targetMode.rawValue).compactMap { lookup[$0] }
    }
    var selectedActionIndex: Int? { orbitActions.firstIndex { $0.id == selectedActionID } }
    var selectedAction: OrbitAction? { orbitActions.first { $0.id == selectedActionID } }
    var compressionLast: Bool { orbitActions.last?.isCompression == true && preferences.orders[mode.rawValue] == nil }
    var parameters: [OrbitParameter] {
        guard let action = orbitActions.first(where: { $0.id == parameterParentID }), let input else { return [] }
        return OrbitParameter.options(for: action, kind: FileKind.detect(input), pageCount: inspector.pageCount)
    }
    var selectedParameterIndex: Int? { parameters.firstIndex { $0.id == selectedParameterID } }
    var parameterLayout: OrbitParameterLayout? {
        guard let index = orbitActions.firstIndex(where: { $0.id == parameterParentID }), !parameters.isEmpty else { return nil }
        return OrbitParameterLayout(parentAngle: OrbitLayout.angle(index: index, count: orbitActions.count, compressionLast: compressionLast), count: parameters.count)
    }
    var prediction: String? {
        if let parameter = parameters.first(where: { $0.id == selectedParameterID }) { return parameter.title + " · " + parameter.subtitle }
        return selectedAction?.subtitle
    }
    func refresh() {
        environment = .discover(); accessibilityGranted = AXIsProcessTrusted()
        if let input { actions = CapabilityCatalog.actions(for: input, environment: environment) }
    }
    func select(_ url: URL) {
        guard stage != .working else { return }
        guard url.isFileURL, let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]), values.isRegularFile == true, values.isSymbolicLink != true else {
            selectionFailed("Choose a regular file. Folders and aliases are not conversion inputs."); return
        }
        input = url; errorMessage = nil; result = nil; stage = .ready; resetInteraction()
        refresh(); inspector.load(url)
    }
    func selectionFailed(_ message: String) {
        guard stage != .working else { return }
        input = nil; actions = []; result = nil; stage = .ready; errorMessage = message
        resetInteraction(); inspector.load(nil)
    }
    func resetInteraction() {
        hoverTask?.cancel(); hoverTask = nil; hoverTargetID = nil; hoverStarted = nil
        selectedActionID = nil; parameterParentID = nil; selectedParameterID = nil; pendingActivationID = nil
    }
    func chooseFile() {
        guard stage != .working else { return }
        let picker = NSOpenPanel(); picker.canChooseDirectories = false; picker.allowsMultipleSelection = true
        picker.title = "Choose files for FileOrbit"; picker.prompt = "Choose"
        picker.begin { [weak self] response in
            Task { @MainActor in
                guard response == .OK, let self else { return }
                if picker.urls.count > 1 { self.onShelf?(picker.urls) }
                else if let url = picker.url { self.select(url) }
            }
        }
    }
    func setMode(_ value: OrbitMode) { guard stage != .working else { return }; mode = value }
    func updateModifiers(_ flags: NSEvent.ModifierFlags) { if let value = OrbitMode.fromModifiers(flags) { setMode(value) } }
    func hover(_ point: CGPoint?) {
        guard stage != .working else { return }
        guard let point else { hoverTask?.cancel(); hoverTargetID = nil; return }
        if let layout = parameterLayout, let index = layout.index(at: point, activeIndex: selectedParameterIndex) {
            boundaryChanged(from: selectedParameterID, to: parameters[index].id)
            selectedParameterID = parameters[index].id; hoverTask?.cancel(); hoverTargetID = nil; return
        }
        if let index = OrbitLayout.actionIndex(at: point, count: orbitActions.count, compressionLast: compressionLast, activeIndex: selectedActionIndex) {
            let action = orbitActions[index]
            boundaryChanged(from: selectedActionID, to: action.id)
            if selectedActionID != action.id { parameterParentID = nil; selectedParameterID = nil }
            selectedActionID = action.id; selectedParameterID = nil
            if hoverTargetID != action.id {
                hoverTask?.cancel(); hoverTargetID = action.id; hoverStarted = .now
                hoverTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(160))
                    guard !Task.isCancelled, let self, self.hoverTargetID == action.id else { return }
                    self.openParameters(action)
                }
            }
        } else {
            hoverTask?.cancel(); hoverTargetID = nil
            let distance = hypot(point.x - OrbitLayout.wheelCenter.x, point.y - OrbitLayout.wheelCenter.y)
            if distance < OrbitLayout.hubRadius || distance > 213 { selectedActionID = nil; selectedParameterID = nil; parameterParentID = nil }
        }
    }
    private func boundaryChanged(from old: String?, to new: String) {
        if old != new { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
    }
    func openParameters(_ action: OrbitAction) {
        guard let input, !OrbitParameter.options(for: action, kind: FileKind.detect(input), pageCount: inspector.pageCount).isEmpty else { return }
        parameterParentID = action.id
    }
    func activate(_ action: OrbitAction) {
        guard stage != .working else { return }
        selectedActionID = action.id
        if let input, FileKind.detect(input) == .pdf, !inspector.metadataLoaded,
           case .file(.convert(let format)) = action.command, [.png, .jpg, .webp].contains(format) {
            pendingActivationID = action.id; return
        }
        if let input, !OrbitParameter.options(for: action, kind: FileKind.detect(input), pageCount: inspector.pageCount).isEmpty {
            openParameters(action); selectedParameterID = nil
        } else { execute(action.command) }
    }
    func execute(_ command: OrbitCommand) {
        guard let input, stage != .working else { return }
        switch command {
        case .file(let operation): run(operation)
        case .redact: onRedact?(input)
        case .shelf: onShelf?([input])
        default: onRoute?(command, input)
        }
    }
    func keyboardMove(_ delta: Int) {
        if !parameters.isEmpty {
            let index = OrbitLayout.nextSelection(selectedParameterIndex ?? (delta > 0 ? -1 : 0), delta: delta, count: parameters.count)
            boundaryChanged(from: selectedParameterID, to: parameters[index].id); selectedParameterID = parameters[index].id
        } else if !orbitActions.isEmpty {
            let index = OrbitLayout.nextSelection(selectedActionIndex ?? (delta > 0 ? -1 : 0), delta: delta, count: orbitActions.count)
            boundaryChanged(from: selectedActionID, to: orbitActions[index].id); selectedActionID = orbitActions[index].id
        }
    }
    func keyboardActivate() {
        if let index = selectedParameterIndex { run(parameters[index].operation) }
        else if let selectedAction { activate(selectedAction) }
        else if let first = orbitActions.first { selectedActionID = first.id }
    }
    func acceptsDrop(at point: CGPoint) -> Bool {
        guard stage != .working else { return false }
        if hypot(point.x - OrbitLayout.wheelCenter.x, point.y - OrbitLayout.wheelCenter.y) <= OrbitLayout.hubRadius { return true }
        if let layout = parameterLayout, layout.index(at: point, activeIndex: selectedParameterIndex) != nil { return true }
        return OrbitLayout.actionIndex(at: point, count: orbitActions.count, compressionLast: compressionLast, activeIndex: selectedActionIndex) != nil
    }
    /// Drop target uses exactly the rendered paths, including active transforms.
    func drop(_ urls: [URL], at point: CGPoint) {
        guard !urls.isEmpty, acceptsDrop(at: point) else { return }
        isDraggingFile = false
        if urls.count > 1 || hypot(point.x - OrbitLayout.wheelCenter.x, point.y - OrbitLayout.wheelCenter.y) <= OrbitLayout.hubRadius {
            onShelf?(urls); return
        }
        let command: OrbitCommand?
        if let layout = parameterLayout, let index = layout.index(at: point, activeIndex: selectedParameterIndex) { command = .file(parameters[index].operation) }
        else if let index = OrbitLayout.actionIndex(at: point, count: orbitActions.count, compressionLast: compressionLast, activeIndex: selectedActionIndex) { command = orbitActions[index].command }
        else { return }
        if input != urls[0] { select(urls[0]) }
        if let command { execute(command) }
    }
    func perform(_ action: FileAction) { activate(OrbitAction(action)) }
    func run(_ operation: FileOperation) {
        guard let input, stage != .working else { return }
        hoverTask?.cancel()
        let token = CancellationToken(); cancellation = token
        stage = .working; errorMessage = nil; cancelling = false; result = nil
        onRunStarted?(input)
        let request = ConversionRequest(input: input, operation: operation), env = environment
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome = Result { try ConversionEngine(environment: env).run(request, cancellation: token) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.cancellation = nil; self.cancelling = false
                switch outcome {
                case .success(let result):
                    self.result = result; self.stage = .result; self.onRunCompleted?(input, result)
                case .failure(let error):
                    self.stage = .ready; self.errorMessage = error.localizedDescription; self.onRunFailed?(error)
                }
            }
        }
    }
    func cancel() { cancelling = true; cancellation?.cancel() }
    func back() { guard stage != .working else { return }; stage = .ready; errorMessage = nil; resetInteraction() }
    func reveal() { if let result { NSWorkspace.shared.activateFileViewerSelecting(result.outputURLs) } }
    func requestAccessibility() {
        guard !FileOrbitRuntime.isPreview else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }
}
