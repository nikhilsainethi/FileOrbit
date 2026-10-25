import AppKit
import Combine
import UniformTypeIdentifiers

/// Persists bookmark references. Originals never move into the shelf.
@MainActor
final class NotchStashModel: ObservableObject {
    struct Item: Identifiable {
        let id: UUID
        let url: URL?
        let isAvailable: Bool
        let isManagedCopy: Bool
        var title: String { url?.lastPathComponent ?? "Unavailable file" }
    }
    private struct Bookmark: Codable {
        let id: UUID
        var data: Data
        let isManagedCopy: Bool
    }
    static let maximumItems = 64
    @Published private(set) var items: [Item] = []
    @Published var message: String?
    private let defaults: UserDefaults
    let managedDirectory: URL
    private var bookmarks: [Bookmark] = []
    private let key = "FileOrbit.notchStash.bookmarks"

    init(defaults: UserDefaults = .standard, managedDirectory: URL? = nil) {
        self.defaults = defaults
        self.managedDirectory = managedDirectory ?? Self.defaultManagedDirectory()
        if let data = defaults.data(forKey: key), data.count <= 8_388_608,
           let stored = try? JSONDecoder().decode([Bookmark].self, from: data) {
            bookmarks = Array(stored.prefix(Self.maximumItems))
        }
        refresh()
    }

    private static func defaultManagedDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "io.fileorbit.development", isDirectory: true)
            .appendingPathComponent("ClipboardPins", isDirectory: true)
    }

    func add(_ urls: [URL]) {
        var known = Set(items.compactMap { $0.url?.standardizedFileURL })
        var rejected = 0
        for rawURL in urls {
            let url = rawURL.standardizedFileURL
            guard !known.contains(url) else { continue }
            guard bookmarks.count < Self.maximumItems, Self.isRegularFile(url) else { rejected += 1; continue }
            do {
                let data = try Self.bookmark(url)
                bookmarks.append(Bookmark(id: UUID(), data: data, isManagedCopy: false)); known.insert(url)
            } catch { rejected += 1 }
        }
        save(); refresh()
        message = rejected > 0 ? "\(rejected) item\(rejected == 1 ? "" : "s") could not be pinned. Choose regular files; the shelf holds up to \(Self.maximumItems)." : nil
    }

    /// Clipboard-only pixels need a real, owned file so a reference can survive relaunch.
    /// The only files removed by remove/clear are these generated copies.
    @discardableResult
    func pin(_ snapshot: ClipboardSnapshot) throws -> URL {
        guard bookmarks.count < Self.maximumItems else { throw SpatialSurfaceError.shelfFull }
        try ClipboardSnapshot.validateImage(snapshot.data)
        let directory = managedDirectory.standardizedFileURL
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let ext = UTType(snapshot.typeIdentifier)?.preferredFilenameExtension ?? "png"
        let url = directory.appendingPathComponent("Clipboard-\(UUID().uuidString).\(ext)")
        try snapshot.data.write(to: url, options: .withoutOverwriting)
        do {
            let data = try Self.bookmark(url)
            bookmarks.append(Bookmark(id: UUID(), data: data, isManagedCopy: true))
            save(); refresh(); message = "Clipboard image pinned locally."
            return url
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    func refresh() {
        items = bookmarks.indices.map { index in
            let record = bookmarks[index]
            var stale = false
            let url = try? URL(resolvingBookmarkData: record.data, options: [.withoutUI, .withoutMounting, .withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
            if stale, let url, let replacement = try? Self.bookmark(url) { bookmarks[index].data = replacement }
            let granted = url?.startAccessingSecurityScopedResource() ?? false
            defer { if granted { url?.stopAccessingSecurityScopedResource() } }
            return Item(id: record.id, url: url, isAvailable: url.map(Self.isRegularFile) ?? false, isManagedCopy: record.isManagedCopy)
        }
        save()
    }

    func remove(_ id: UUID) {
        if let item = items.first(where: { $0.id == id }), item.isManagedCopy, let url = item.url { removeManagedCopy(url) }
        bookmarks.removeAll { $0.id == id }; save(); refresh()
    }

    func clear() {
        for item in items where item.isManagedCopy { if let url = item.url { removeManagedCopy(url) } }
        bookmarks.removeAll(); save(); refresh(); message = nil
    }

    func reveal(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }), item.isAvailable, let url = item.url else {
            message = "This file is no longer available. Remove its reference or pin it again."; return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func removeManagedCopy(_ url: URL) {
        let file = url.standardizedFileURL
        guard file.deletingLastPathComponent() == managedDirectory.standardizedFileURL,
              file.lastPathComponent.hasPrefix("Clipboard-"),
              UUID(uuidString: String(file.deletingPathExtension().lastPathComponent.dropFirst("Clipboard-".count))) != nil else { return }
        try? FileManager.default.removeItem(at: file)
    }

    private func save() {
        if bookmarks.isEmpty { defaults.removeObject(forKey: key) }
        else if let encoded = try? JSONEncoder().encode(bookmarks) { defaults.set(encoded, forKey: key) }
    }

    private static func bookmark(_ url: URL) throws -> Data {
        do { return try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil) }
        catch { return try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) }
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        guard url.isFileURL, let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }
}

enum SpatialSurfaceError: LocalizedError {
    case clipboardChanged, invalidImage, clipboardWriteFailed, shelfFull
    var errorDescription: String? {
        switch self {
        case .clipboardChanged: return "The clipboard changed while this image was processing. Your newer clipboard content was kept."
        case .invalidImage: return "Choose one supported image no larger than 64 MB or 32 megapixels. Animated and multipage images are not supported."
        case .clipboardWriteFailed: return "macOS could not place this image on the clipboard."
        case .shelfFull: return "The Notch Shelf holds up to 64 files. Remove a reference before pinning another image."
        }
    }
}
