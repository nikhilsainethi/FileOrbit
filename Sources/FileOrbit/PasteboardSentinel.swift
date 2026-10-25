import AppKit
import Combine
import ImageIO
import UniformTypeIdentifiers

struct ClipboardSnapshot: Identifiable, Sendable {
    enum Origin: Equatable, Sendable { case clipboard, screenshot(URL) }
    static let maximumBytes = 64 * 1024 * 1024
    static let generatedMarker = "io.fileorbit.generated"
    let id: UUID
    let data: Data
    let typeIdentifier: String
    let changeCount: Int
    let origin: Origin
    let createdAt: Date

    init(id: UUID = UUID(), data: Data, typeIdentifier: String, changeCount: Int, origin: Origin = .clipboard, createdAt: Date = Date()) {
        self.id = id; self.data = data; self.typeIdentifier = typeIdentifier
        self.changeCount = changeCount; self.origin = origin; self.createdAt = createdAt
    }
    var title: String { if case .screenshot = origin { return "New screenshot" }; return "Clipboard image" }
    var preferredExtension: String { UTType(typeIdentifier)?.preferredFilenameExtension ?? "png" }

    static func validateImage(_ data: Data) throws {
        guard !data.isEmpty, data.count <= maximumBytes,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 32_000_000 / height else { throw SpatialSurfaceError.invalidImage }
    }
}

/// An opt-in observer, not a clipboard history. Image bytes live only in memory
/// until an explicit action; screenshot discovery never requests screen capture.
@MainActor
final class PasteboardSentinel {
    var onSnapshot: ((ClipboardSnapshot) -> Void)?
    var onError: ((String) -> Void)?
    private let preferences: SpatialPreferences
    private let pasteboard: NSPasteboard
    private var gate: ClipboardRevisionGate
    private var timer: Timer?
    private var query: NSMetadataQuery?
    private var queryObservers: [NSObjectProtocol] = []
    private var screenshotGate = ScreenshotObservationGate(startedAt: Date())
    private var screenshotCandidates: [URL] = []
    private var subscriptions = Set<AnyCancellable>()
    private var validationTask: Task<Void, Never>?
    private var screenshotTask: Task<Void, Never>?
    private var generation = UUID()
    private var started = false
    private var startedAt = Date()

    init(preferences: SpatialPreferences = .shared, pasteboard: NSPasteboard = .general) {
        self.preferences = preferences; self.pasteboard = pasteboard
        gate = ClipboardRevisionGate(initial: pasteboard.changeCount)
        preferences.$clipboardEnabled.dropFirst().sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshPreferences() }
        }.store(in: &subscriptions)
        preferences.$screenshotEnabled.dropFirst().sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshPreferences() }
        }.store(in: &subscriptions)
    }

    func start() {
        guard !started else { refreshPreferences(); return }
        started = true; startedAt = Date(); screenshotGate = ScreenshotObservationGate(startedAt: startedAt)
        gate = ClipboardRevisionGate(initial: pasteboard.changeCount)
        refreshPreferences()
    }

    func stop() {
        started = false; generation = UUID()
        timer?.invalidate(); timer = nil
        validationTask?.cancel(); validationTask = nil
        screenshotTask?.cancel(); screenshotTask = nil
        stopScreenshotQuery()
    }

    func refreshPreferences() {
        guard started else { return }
        if preferences.clipboardEnabled || preferences.screenshotEnabled {
            if timer == nil {
                gate = ClipboardRevisionGate(initial: pasteboard.changeCount)
                timer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.poll() }
                }
                timer?.tolerance = 0.15
            }
        } else {
            generation = UUID(); timer?.invalidate(); timer = nil
            validationTask?.cancel(); validationTask = nil
            screenshotTask?.cancel(); screenshotTask = nil
        }
        if preferences.screenshotEnabled { startScreenshotQuery() }
        else { stopScreenshotQuery() }
    }

    /// Immediate revision check and synchronous write prevent a delayed operation
    /// from knowingly overwriting newer user content. macOS provides no cross-app
    /// atomic compare-and-swap API for NSPasteboard.
    func commit(data: Data, typeIdentifier: String, for snapshot: ClipboardSnapshot) throws {
        try ClipboardSnapshot.validateImage(data)
        guard let type = UTType(typeIdentifier), type.conforms(to: .image),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let encodedIdentifier = CGImageSourceGetType(source),
              UTType(encodedIdentifier as String) == type else { throw SpatialSurfaceError.invalidImage }
        guard gate.canCommit(expected: snapshot.changeCount, current: pasteboard.changeCount) else {
            throw SpatialSurfaceError.clipboardChanged
        }
        let item = NSPasteboardItem()
        guard item.setData(data, forType: NSPasteboard.PasteboardType(typeIdentifier)),
              item.setString("FileOrbit", forType: NSPasteboard.PasteboardType(ClipboardSnapshot.generatedMarker)) else {
            throw SpatialSurfaceError.clipboardWriteFailed
        }
        pasteboard.clearContents()
        let success = pasteboard.writeObjects([item])
        gate.didWrite(pasteboard.changeCount)
        guard success else { throw SpatialSurfaceError.clipboardWriteFailed }
    }

    func isCurrent(_ snapshot: ClipboardSnapshot) -> Bool {
        gate.canCommit(expected: snapshot.changeCount, current: pasteboard.changeCount)
    }

    private func poll() {
        guard started else { return }
        if preferences.clipboardEnabled { inspectClipboardIfChanged() }
        if preferences.screenshotEnabled { inspectScreenshotCandidates() }
    }

    private func inspectClipboardIfChanged() {
        let revision = pasteboard.changeCount
        guard gate.observe(revision) else { return }
        validationTask?.cancel()
        let types = Set((pasteboard.types ?? []).map(\.rawValue))
        let privateTypes: Set<String> = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType", "com.agilebits.onepassword", ClipboardSnapshot.generatedMarker]
        guard types.isDisjoint(with: privateTypes) else { return }
        let candidates = [UTType.png.identifier, UTType.tiff.identifier, UTType.jpeg.identifier, UTType.heic.identifier, UTType.webP.identifier]
        guard let identifier = candidates.first(where: { types.contains($0) }),
              let data = pasteboard.data(forType: NSPasteboard.PasteboardType(identifier)),
              data.count <= ClipboardSnapshot.maximumBytes,
              pasteboard.changeCount == revision else { return }
        let snapshot = ClipboardSnapshot(data: data, typeIdentifier: identifier, changeCount: revision)
        let requestGeneration = generation
        validationTask = Task { [weak self] in
            let valid = await Task.detached(priority: .utility) { (try? ClipboardSnapshot.validateImage(data)) != nil }.value
            guard !Task.isCancelled, let self, self.started, self.preferences.clipboardEnabled,
                  requestGeneration == self.generation, valid, self.pasteboard.changeCount == revision else { return }
            self.onSnapshot?(snapshot)
        }
    }

    private func startScreenshotQuery() {
        guard query == nil else { return }
        // Start at enable time, so opting in never resurfaces old screenshots.
        startedAt = Date(); screenshotGate = ScreenshotObservationGate(startedAt: startedAt)
        let query = NSMetadataQuery()
        var scopes: [Any] = [NSMetadataQueryUserHomeScope]
        if let location = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"),
           !location.isEmpty {
            let directory = URL(fileURLWithPath: (location as NSString).expandingTildeInPath, isDirectory: true)
            if (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { scopes.append(directory) }
        }
        query.searchScopes = scopes
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1 AND kMDItemFSCreationDate >= %@", startedAt as NSDate)
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSCreationDateKey, ascending: false)]
        query.notificationBatchingInterval = 0.5
        self.query = query
        for name in [NSNotification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            queryObservers.append(NotificationCenter.default.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.collectScreenshots() }
            })
        }
        if !query.start() {
            stopScreenshotQuery()
            onError?("Screenshot discovery could not start. Clipboard image suggestions remain available. Check Spotlight indexing and folder access.")
        }
    }

    private func stopScreenshotQuery() {
        query?.stop(); query = nil
        queryObservers.forEach { NotificationCenter.default.removeObserver($0) }; queryObservers.removeAll()
        screenshotCandidates.removeAll(); screenshotTask?.cancel(); screenshotTask = nil
    }

    private func collectScreenshots() {
        guard let query, preferences.screenshotEnabled else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }
        screenshotCandidates = query.results.prefix(64).compactMap { result in
            guard let item = result as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { return nil }
            return URL(fileURLWithPath: path)
        }
    }

    private func inspectScreenshotCandidates() {
        guard screenshotTask == nil else { return }
        for url in screenshotCandidates {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  let created = values.creationDate, let modified = values.contentModificationDate,
                  let bytes = values.fileSize,
                  screenshotGate.observe(url: url, created: created, bytes: bytes, modified: modified.timeIntervalSince1970) else { continue }
            let revision = pasteboard.changeCount, requestGeneration = generation
            screenshotTask = Task { [weak self] in
                let snapshot = await Task.detached(priority: .utility) { () -> ClipboardSnapshot? in
                    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
                    defer { try? handle.close() }
                    guard let data = try? handle.read(upToCount: ClipboardSnapshot.maximumBytes + 1), data.count == bytes,
                          (try? ClipboardSnapshot.validateImage(data)) != nil,
                          let after = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                          after.fileSize == bytes, after.contentModificationDate == modified,
                          let source = CGImageSourceCreateWithData(data as CFData, nil), let sourceType = CGImageSourceGetType(source) else { return nil }
                    return ClipboardSnapshot(data: data, typeIdentifier: sourceType as String, changeCount: revision, origin: .screenshot(url))
                }.value
                guard let self else { return }
                self.screenshotTask = nil
                guard !Task.isCancelled, self.started, self.preferences.screenshotEnabled,
                      requestGeneration == self.generation, self.pasteboard.changeCount == revision,
                      let snapshot else { return }
                self.onSnapshot?(snapshot)
            }
            return
        }
    }
}
