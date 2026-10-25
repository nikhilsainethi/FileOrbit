import AppKit
import SwiftUI
import Combine
import UniformTypeIdentifiers
import FileOrbitCore

@MainActor final class CommercialCoordinator: NSObject, NSWindowDelegate {
    let model: AppModel
    let notch = NotchPortalWindowController()
    let sentinel = PasteboardSentinel()
    lazy var orb = ClipboardOrbWindowController(sentinel: sentinel)
    private let neural = NeuralProcessingActor()
    private var reviewWindow: NSWindow?
    private var review: SanitizeReviewModel?
    private var reviewCleanup: (() -> Void)?
    private var pipelineToken: CancellationToken?
    private var isPipelineRunning = false
    private var orbToken: CancellationToken?
    private var subscriptions = Set<AnyCancellable>()
    init(model: AppModel) { self.model = model; super.init() }

    func start() {
        model.onCommercial = { [weak self] command, url in self?.execute(command, input: url) }
        model.onSanitize = { [weak self] url, style in self?.showReview(input: url, style: style) }
        sentinel.onSnapshot = { [weak self] snapshot in self?.orb.show(snapshot: snapshot, at: nil) }
        sentinel.onError = { [weak self] message in self?.model.errorMessage = message }
        orb.onCancelProcessing = { [weak self] in self?.orbToken?.cancel() }
        orb.onAction = { [weak self] action, snapshot in self?.performOrb(action, snapshot: snapshot) }
        notch.onPipeline = { [weak self] urls, id in self?.runPipeline(urls, id: id) }
        notch.onCancelPipeline = { [weak self] in self?.pipelineToken?.cancel() }
        SpatialPreferences.shared.objectWillChange.sink { [weak self] in
            Task { @MainActor [weak self] in self?.refresh() }
        }.store(in: &subscriptions)
        sentinel.start()
        refresh()
    }
    func showOrbDemo() {
        do {
            let assets = try OnboardingSandboxAssets.create()
            defer { try? FileManager.default.removeItem(at: assets.directory) }
            let snapshot = ClipboardSnapshot(data: try Data(contentsOf: assets.portrait), typeIdentifier: UTType.png.identifier, changeCount: NSPasteboard.general.changeCount)
            orb.show(snapshot: snapshot)
        } catch { model.errorMessage = error.localizedDescription }
    }
    func refresh() {
        notch.model.pipelineTitle = PinnedPipeline(rawValue: SpatialPreferences.shared.favoritePipelineID)?.title ?? "Choose a pipeline"
        notch.refreshPreferences()
        // The isolated preview never begins global clipboard observation on its own.
        // Opt-in is available in its Settings and uses the preview preference domain.
        sentinel.refreshPreferences()
    }
    func stop() { sentinel.stop(); notch.stop(); orb.dismiss(); pipelineToken?.cancel(); orbToken?.cancel(); review?.cancel(); reviewCleanup?(); reviewCleanup = nil }

    func execute(_ command: OrbitCommand, input: URL) {
        guard model.stage != .working else { return }
        let isNeural: Bool
        switch command { case .liftSubject: isNeural = true; default: isNeural = false }
        let clipboardRevision = NSPasteboard.general.changeCount
        let token = model.beginCommercial(input: input, neural: isNeural), directory = model.outputDirectory
        model.impactCategory = isNeural ? .isolation : .conversion
        Task { [weak self, neural] in
            guard let self else { return }
            do {
                var result: ConversionResult
                var copyOutcome: ClipboardWriteOutcome = .written
                switch command {
                case .liftSubject(let output, let copy):
                    result = try await neural.liftSubject(input: input, output: output, outputDirectory: directory, cancellation: token)
                    if copy, let url = result.outputURLs.first { copyOutcome = token.isCancelled ? .cancelled : FileOrbitClipboard.write(try Data(contentsOf: url), type: .png, expectedRevision: clipboardRevision) }
                case .developer(let operation):
                    result = try await Task.detached(priority: .userInitiated) { try DeveloperPayloadEngine().run(input: input, operation: operation, outputDirectory: directory, cancellation: token) }.value
                    if operation == .extractPalette,
                       let png = result.outputURLs.first(where: { $0.pathExtension == "png" }) {
                        let text = result.outputURLs.first(where: { $0.pathExtension == "txt" }).flatMap { try? String(contentsOf: $0, encoding: .utf8) }
                        copyOutcome = token.isCancelled ? .cancelled : FileOrbitClipboard.write(try Data(contentsOf: png), type: .png, text: text, expectedRevision: clipboardRevision)
                    }
                default: throw ConversionError.unsupported("This action is unavailable.")
                }
                if let note = copyOutcome.copyNote { result = ConversionResult(outputURLs: result.outputURLs, inputBytes: result.inputBytes, outputBytes: result.outputBytes, note: "File saved. " + note + ".", undoURLs: result.undoURLs) }
                self.model.finishCommercial(input: input, outcome: .success(result))
            } catch { self.model.finishCommercial(input: input, outcome: .failure(error)) }
        }
    }
    func showReview(input: URL, style: SanitizeStyle, directory: URL? = nil,
                    completed: (@MainActor (URL, ConversionResult) throws -> Void)? = nil, cleanup: (() -> Void)? = nil) {
        guard reviewWindow == nil, model.stage != .working else { cleanup?(); model.errorMessage = "Finish or close the current operation before starting a privacy review."; return }
        model.onDismiss?(); model.stage = .working; model.neuralBusy = false
        let editor = SanitizeReviewModel(input: input, style: style, outputDirectory: directory ?? model.outputDirectory)
        review = editor; reviewCleanup = cleanup
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 760, height: 760), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "FileOrbit · Sanitize review"; window.isReleasedWhenClosed = false; window.delegate = self
        window.contentView = NSHostingView(rootView: SanitizeReviewView(model: editor, onCompleted: { [weak self, weak window] url, result in
            guard let self else { return }
            do {
                if let completed { try completed(url, result) }
                else {
                    self.model.impactCategory = .redaction
                    self.model.finishCommercial(input: url, outcome: .success(result))
                }
                window?.close()
            } catch { editor.error = error.localizedDescription }
        }, onCancel: { [weak window] in window?.close() }, exportTitle: completed == nil ? "Save reviewed copy" : "Replace clipboard"))
        reviewWindow = window; window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === reviewWindow else { return }
        review?.cancel(); review = nil; reviewWindow = nil
        if model.stage == .working { model.stage = .ready }
        reviewCleanup?(); reviewCleanup = nil
    }
    private func runPipeline(_ urls: [URL], id: String) {
        guard !isPipelineRunning, model.stage != .working, !urls.isEmpty, urls.count <= 50, let pipeline = PinnedPipeline(rawValue: id) else { notch.pipelineFinished(message: "Choose a pipeline and finish the current job first."); return }
        guard urls.allSatisfy({ FileKind.detect($0) == .image }) else { notch.pipelineFinished(message: "This pipeline accepts images. Pin other files to Quick Stash."); return }
        isPipelineRunning = true; model.stage = .working; model.neuralBusy = false
        let token = CancellationToken(); pipelineToken = token; model.commercialCancellation = token
        let environment = model.environment, sandboxInput = model.input, sandboxDirectory = model.outputDirectory
        var clipboardRevision = NSPasteboard.general.changeCount
        var copyOutcome: ClipboardWriteOutcome = .written
        Task { [weak self] in
            guard let self else { return }
            defer { self.model.stage = .ready; self.model.commercialCancellation = nil }
            var successes = 0
            for url in urls {
                do {
                    try token.check()
                    let destination = url == sandboxInput ? sandboxDirectory : nil
                    let result = try await Task.detached(priority: .userInitiated) { try PipelineExecutor(environment: environment).run(input: url, pipeline: pipeline, outputDirectory: destination, cancellation: token) }.value
                    successes += 1; self.model.impactCategory = pipeline == .compress ? .compression : .conversion
                    self.model.onRunCompleted?(url, result)
                    if let last = result.outputURLs.first, let type = UTType(filenameExtension: last.pathExtension) {
                        if copyOutcome == .written {
                            copyOutcome = token.isCancelled ? .cancelled : FileOrbitClipboard.write(try Data(contentsOf: last), type: .init(type.identifier), expectedRevision: clipboardRevision)
                            if copyOutcome == .written { clipboardRevision = NSPasteboard.general.changeCount }
                        }
                    }
                } catch { self.notch.pipelineFinished(message: "\(successes) saved. \(error.localizedDescription)"); self.isPipelineRunning = false; self.pipelineToken = nil; return }
            }
            self.notch.pipelineFinished(message: "\(successes) saved · " + (copyOutcome.copyNote ?? "last image copied"))
            self.isPipelineRunning = false; self.pipelineToken = nil
        }
    }
    private func performOrb(_ action: ClipboardOrbAction, snapshot: ClipboardSnapshot) {
        do {
            guard sentinel.isCurrent(snapshot) else { throw ConversionError.invalidInput("The clipboard changed. Your newer copy was kept.") }
            if action == .pin { _ = try notch.pin(snapshot); orb.finish(message: "Pinned to Quick Stash", snapshotID: snapshot.id); return }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("fileorbit-orb-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let input = directory.appendingPathComponent("Clipboard." + snapshot.preferredExtension)
            try snapshot.data.write(to: input)
            if action == .sanitize {
                orb.dismiss()
                showReview(input: input, style: .obsidian, directory: directory, completed: { [weak self] _, result in
                    guard let self, let output = result.outputURLs.first else { return }
                    try self.sentinel.commit(data: Data(contentsOf: output), typeIdentifier: UTType.png.identifier, for: snapshot)
                    ImpactStore.shared.record(id: UUID(), category: .redaction, inputBytes: result.inputBytes, outputBytes: result.outputBytes)
                }, cleanup: { try? FileManager.default.removeItem(at: directory) })
                return
            }
            let token = CancellationToken(); orbToken?.cancel(); orbToken = token
            let operation: FileOperation = action == .webp ? .convert(.webp) : .compress(.balanced), environment = model.environment
            Task { [weak self] in
                defer { try? FileManager.default.removeItem(at: directory) }
                guard let self else { return }
                do {
                    let result = try await Task.detached(priority: .userInitiated) { try ConversionEngine(environment: environment).run(ConversionRequest(input: input, operation: operation, outputDirectory: directory), cancellation: token) }.value
                    guard let output = result.outputURLs.first, let type = UTType(filenameExtension: output.pathExtension) else { throw ConversionError.failed("No image was produced.") }
                    try token.check()
                    try self.sentinel.commit(data: Data(contentsOf: output), typeIdentifier: type.identifier, for: snapshot)
                    ImpactStore.shared.record(id: snapshot.id, category: action == .webp ? .conversion : .compression, inputBytes: result.inputBytes, outputBytes: result.outputBytes)
                    self.orb.finish(message: "Ready for your next paste", snapshotID: snapshot.id)
                } catch { self.orb.finish(message: error.localizedDescription, success: false, snapshotID: snapshot.id) }
            }
        } catch { orb.finish(message: error.localizedDescription, success: false, snapshotID: snapshot.id) }
    }
}
