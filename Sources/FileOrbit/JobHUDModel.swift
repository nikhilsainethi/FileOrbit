import AppKit
import Combine
import CryptoKit
import Darwin
import FileOrbitCore

/// Captures only the files published by the engine. Folders are deliberately
/// never trashed: someone may have put another file into a page-export folder.
struct OutputUndoRecord: Sendable {
    private struct Fingerprint: Equatable, Sendable {
        let identity: String
        let size: Int64
        let modifiedSeconds: Int64
        let modifiedNanos: Int64
        let digest: String

        static func read(_ url: URL) throws -> Fingerprint {
            let descriptor = url.withUnsafeFileSystemRepresentation { path in path.map { Darwin.open($0, O_RDONLY | O_NOFOLLOW) } ?? -1 }
            guard descriptor >= 0 else { throw UndoError.changed }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            defer { try? handle.close() }
            var before = stat(), after = stat()
            guard fstat(descriptor, &before) == 0, before.st_mode & S_IFMT == S_IFREG else { throw UndoError.changed }
            var hash = SHA256()
            while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty { hash.update(data: chunk) }
            guard fstat(descriptor, &after) == 0,
                  before.st_size == after.st_size,
                  before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
                  before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec else { throw UndoError.changed }
            return Fingerprint(identity: "\(before.st_dev):\(before.st_ino)", size: before.st_size,
                               modifiedSeconds: Int64(before.st_mtimespec.tv_sec), modifiedNanos: Int64(before.st_mtimespec.tv_nsec),
                               digest: hash.finalize().map { String(format: "%02x", $0) }.joined())
        }
    }
    enum UndoError: LocalizedError {
        case changed, unsafe
        var errorDescription: String? {
            switch self {
            case .changed: return "Undo is unavailable because an output was moved, removed, or edited. Your files were left in place."
            case .unsafe: return "Undo could not safely identify the new output files."
            }
        }
    }
    private let files: [(url: URL, canonicalPath: String, fingerprint: Fingerprint)]

    static func capture(source: URL, outputs: [URL]) throws -> OutputUndoRecord {
        guard !outputs.isEmpty else { throw UndoError.unsafe }
        let sourceFingerprint = try Fingerprint.read(source)
        let sourcePath = source.resolvingSymlinksInPath().standardizedFileURL.path
        var seen = Set<String>()
        let files = try outputs.map { url -> (URL, String, Fingerprint) in
            guard url.isFileURL else { throw UndoError.unsafe }
            let canonical = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard canonical != sourcePath, seen.insert(canonical).inserted else { throw UndoError.unsafe }
            let fingerprint = try Fingerprint.read(url)
            guard fingerprint.identity != sourceFingerprint.identity else { throw UndoError.unsafe }
            return (url, canonical, fingerprint)
        }
        return OutputUndoRecord(files: files)
    }

    @discardableResult func validate() throws -> Bool {
        for (url, canonical, captured) in files {
            guard url.resolvingSymlinksInPath().standardizedFileURL.path == canonical,
                  try Fingerprint.read(url) == captured else { throw UndoError.changed }
        }
        return true
    }

    func undo(trash: (URL) throws -> Void = { url in try FileManager.default.trashItem(at: url, resultingItemURL: nil) }) throws {
        try validate()
        for (url, canonical, captured) in files {
            guard url.resolvingSymlinksInPath().standardizedFileURL.path == canonical,
                  try Fingerprint.read(url) == captured else { throw UndoError.changed }
            try trash(url)
        }
    }
}

struct JobHistoryEntry: Identifiable, Codable {
    let id: UUID
    let date: Date
    let inputName: String
    let outputPaths: [String]
    let inputBytes: Int64
    let outputBytes: Int64
    var outputURLs: [URL] { outputPaths.map { URL(fileURLWithPath: $0) } }
}

@MainActor
final class JobHistory: ObservableObject {
    static let shared = JobHistory()
    @Published private(set) var entries: [JobHistoryEntry] = []
    private let defaults: UserDefaults
    private let storageKey = "FileOrbit.recentHistory"
    private var remember: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        remember = defaults.bool(forKey: "FileOrbit.rememberHistory")
        if remember, let data = defaults.data(forKey: storageKey), let saved = try? JSONDecoder().decode([JobHistoryEntry].self, from: data) {
            entries = Array(saved.prefix(20))
        } else { defaults.removeObject(forKey: storageKey) }
    }
    func record(input: URL, result: ConversionResult) {
        entries.insert(JobHistoryEntry(id: UUID(), date: Date(), inputName: input.lastPathComponent,
                                       outputPaths: result.outputURLs.map(\.path), inputBytes: result.inputBytes, outputBytes: result.outputBytes), at: 0)
        entries = Array(entries.prefix(20))
        persist()
    }
    func setRememberHistory(_ enabled: Bool) {
        remember = enabled
        defaults.set(enabled, forKey: "FileOrbit.rememberHistory")
        persist()
    }
    func clear() { entries = []; defaults.removeObject(forKey: storageKey) }
    private func persist() {
        if remember { defaults.set(try? JSONEncoder().encode(entries), forKey: storageKey) }
        else { defaults.removeObject(forKey: storageKey) }
    }
}

@MainActor
final class JobHUDModel: ObservableObject {
    enum Phase: Equatable { case idle, running, complete, failed, undone }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var input: URL?
    @Published private(set) var result: ConversionResult?
    @Published private(set) var error: String?
    @Published private(set) var progress: Double?
    @Published private(set) var canUndo = false
    @Published private(set) var isUndoing = false
    @Published private(set) var isCancelling = false
    var onQuickLook: (() -> Void)?
    var onReveal: (() -> Void)?
    var onCopy: (() -> Void)?
    var onUndo: (() -> Void)?
    var onCancel: (() -> Void)?
    private var undoRecord: OutputUndoRecord?
    private var generation = UUID()

    var title: String {
        switch phase {
        case .idle: return "FileOrbit"
        case .running: return input?.lastPathComponent ?? "Processing files…"
        case .complete: return result?.outputURLs.count == 1 ? result?.outputURLs.first?.lastPathComponent ?? "Saved" : "\(result?.outputURLs.count ?? 0) files saved"
        case .failed: return "Couldn’t finish"
        case .undone: return "Moved output to Trash"
        }
    }
    var detail: String {
        if let error { return error }
        if isCancelling && phase == .running { return "Stopping… Your original is unchanged" }
        if phase == .undone { return "Your original is unchanged" }
        guard let result else { return "Processing locally…" }
        let before = ByteCountFormatter.string(fromByteCount: result.inputBytes, countStyle: .file)
        let after = ByteCountFormatter.string(fromByteCount: result.outputBytes, countStyle: .file)
        let savings = result.inputBytes > 0 && result.outputBytes < result.inputBytes
            ? " · \(Int((1 - Double(result.outputBytes) / Double(result.inputBytes)) * 100))% smaller" : ""
        return "\(before) → \(after)\(savings)"
    }

    func setRunning(input: URL?, progress: Double? = nil) {
        generation = UUID(); self.input = input; self.progress = progress.map { min(1, max(0, $0)) }
        result = nil; error = nil; undoRecord = nil; canUndo = false; isUndoing = false; isCancelling = false; phase = .running
    }
    func updateProgress(completed: Int, total: Int) {
        progress = total > 0 ? min(1, max(0, Double(completed) / Double(total))) : nil
    }
    func complete(input: URL, result: ConversionResult) {
        let id = UUID(); generation = id
        self.input = input; self.result = result; phase = .complete; progress = 1; error = nil
        canUndo = false; undoRecord = nil; isCancelling = false; isUndoing = false
        JobHistory.shared.record(input: input, result: result)
        Task { [weak self] in
            let record = await Task.detached(priority: .utility) { try? OutputUndoRecord.capture(source: input, outputs: result.outputURLs) }.value
            guard let self, self.generation == id else { return }
            self.undoRecord = record; self.canUndo = record != nil
        }
    }
    func fail(_ message: String) {
        generation = UUID(); phase = .failed; error = message; canUndo = false; undoRecord = nil
        result = nil; progress = nil; isCancelling = false; isUndoing = false
    }
    func fail(_ error: Error) { fail(error.localizedDescription) }
    func cancel() { guard phase == .running, !isCancelling, let onCancel else { return }; isCancelling = true; onCancel() }
    func quickLook() { onQuickLook?() }
    func reveal() {
        if let onReveal { onReveal(); return }
        guard let urls = result?.outputURLs else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
    func copyURLs() {
        if let onCopy { onCopy(); return }
        guard let urls = result?.outputURLs, !urls.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(urls as [NSURL])
    }
    func undo() {
        if let onUndo { onUndo(); return }
        guard let undoRecord, canUndo, !isUndoing else { return }
        isUndoing = true; canUndo = false
        let id = generation
        Task { [weak self] in
            let outcome = await Task.detached(priority: .utility) { Result { try undoRecord.undo() } }.value
            guard let self, self.generation == id else { return }
            self.isUndoing = false; self.undoRecord = nil
            switch outcome {
            case .success: self.phase = .undone
            case .failure(let error): self.error = error.localizedDescription
            }
        }
    }
}
