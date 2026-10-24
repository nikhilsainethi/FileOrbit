import AppKit
import SwiftUI
import FileOrbitCore

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
    private var cancellation: CancellationToken?
    var onSettings: (() -> Void)?
    var onDismiss: (() -> Void)?

    var inputSize: String {
        guard let input, let attrs = try? FileManager.default.attributesOfItem(atPath: input.path), let bytes = attrs[.size] as? NSNumber else { return "" }
        return Self.bytes(bytes.int64Value)
    }
    var dependencyHint: String? {
        guard let input else { return nil }
        return CapabilityCatalog.unavailableReason(for: input, environment: environment)
    }
    static func bytes(_ count: Int64) -> String { ByteCountFormatter.string(fromByteCount: count, countStyle: .file) }
    func refresh() {
        environment = .discover()
        accessibilityGranted = AXIsProcessTrusted()
        if let input { actions = CapabilityCatalog.actions(for: input, environment: environment) }
    }
    func select(_ url: URL) {
        guard stage != .working else { return }
        guard url.isFileURL, let values = try? url.resourceValues(forKeys: [.isRegularFileKey]), values.isRegularFile == true else {
            selectionFailed("Choose a regular file. Folders and aliases are not conversion inputs.")
            return
        }
        input = url; errorMessage = nil; result = nil; stage = .ready
        refresh()
    }
    func selectionFailed(_ message: String) {
        guard stage != .working else { return }
        input = nil; actions = []; result = nil; stage = .ready; errorMessage = message
    }
    func chooseFile() {
        guard stage != .working else { return }
        let picker = NSOpenPanel()
        picker.canChooseDirectories = false; picker.allowsMultipleSelection = false
        picker.title = "Choose a file for FileOrbit"
        picker.prompt = "Choose file"
        picker.begin { [weak self] response in
            Task { @MainActor in
                if response == .OK, let url = picker.url { self?.select(url) }
            }
        }
    }
    func perform(_ action: FileAction) {
        if case .compress = action.operation { preset = .balanced; stage = .compression; errorMessage = nil }
        else { run(action.operation) }
    }
    func run(_ operation: FileOperation) {
        guard let input, stage != .working else { return }
        let token = CancellationToken()
        cancellation = token; stage = .working; errorMessage = nil; cancelling = false; result = nil
        let request = ConversionRequest(input: input, operation: operation)
        let env = environment
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome = Result { try ConversionEngine(environment: env).run(request, cancellation: token) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.cancellation = nil; self.cancelling = false
                switch outcome {
                case .success(let result): self.result = result; self.stage = .result
                case .failure(let error):
                    self.stage = .ready
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    func cancel() { cancelling = true; cancellation?.cancel() }
    func back() { guard stage != .working else { return }; stage = .ready; errorMessage = nil }
    func reveal() { if let result { NSWorkspace.shared.activateFileViewerSelecting(result.outputURLs) } }
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }
}
