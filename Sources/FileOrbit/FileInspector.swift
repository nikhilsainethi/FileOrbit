import AppKit
import Combine
import ImageIO
import PDFKit
import QuickLookThumbnailing

struct FileMetadataSnapshot: Sendable {
    let bytes: Int64
    let pageCount: Int?
    let itemCount: Int?
    let dimensions: String?
    var sizeText: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
    var detail: String {
        var parts = [sizeText]
        if let pageCount { parts.append("\(pageCount) page\(pageCount == 1 ? "" : "s")") }
        else if let itemCount, itemCount > 1 { parts.append("\(itemCount) frames") }
        if let dimensions { parts.append(dimensions) }
        return parts.joined(separator: " · ")
    }
    static func read(_ url: URL) throws -> FileMetadataSnapshot {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else { throw CocoaError(.fileReadUnsupportedScheme) }
        var pages: Int?, frames: Int?, dimensions: String?
        if url.pathExtension.lowercased() == "pdf" { pages = PDFDocument(url: url)?.pageCount }
        else if let image = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) {
            frames = CGImageSourceGetCount(image)
            if let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
               let width = properties[kCGImagePropertyPixelWidth] as? Int,
               let height = properties[kCGImagePropertyPixelHeight] as? Int {
                dimensions = "\(width) × \(height)"
            }
        }
        return FileMetadataSnapshot(bytes: Int64(values.fileSize ?? 0), pageCount: pages, itemCount: frames, dimensions: dimensions)
    }
}

/// One inspector per presented file. Both asynchronous completion paths check
/// the generation, so a slow Quick Look provider cannot replace a newer file.
@MainActor
final class FileInspector: ObservableObject {
    @Published private(set) var thumbnail: NSImage?
    @Published private(set) var fallbackIcon: NSImage?
    @Published private(set) var sizeText = ""
    @Published private(set) var pageCount: Int?
    @Published private(set) var itemCount: Int?
    @Published private(set) var metadataText = ""
    @Published private(set) var metadataLoaded = false
    @Published private(set) var isLoading = false
    private var generation = UUID()
    private var request: QLThumbnailGenerator.Request?
    private var metadataTask: Task<Void, Never>?

    func load(_ url: URL?) {
        generation = UUID()
        let id = generation
        if let request { QLThumbnailGenerator.shared.cancel(request) }
        request = nil; metadataTask?.cancel()
        thumbnail = nil; fallbackIcon = nil; sizeText = ""; pageCount = nil; itemCount = nil; metadataText = ""; metadataLoaded = false; isLoading = false
        guard let url, url.isFileURL, FileManager.default.fileExists(atPath: url.path) else { return }
        fallbackIcon = NSWorkspace.shared.icon(forFile: url.path)
        isLoading = true
        metadataTask = Task { [weak self] in
            let metadata = await Task.detached(priority: .utility) { try? FileMetadataSnapshot.read(url) }.value
            guard !Task.isCancelled, let self, self.generation == id else { return }
            if let metadata {
                self.sizeText = metadata.sizeText; self.pageCount = metadata.pageCount
                self.itemCount = metadata.itemCount; self.metadataText = metadata.detail
            }
            self.metadataLoaded = true
        }
        let newRequest = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 160, height: 160), scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
        request = newRequest
        QLThumbnailGenerator.shared.generateBestRepresentation(for: newRequest) { [weak self] representation, _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == id else { return }
                self.thumbnail = representation?.nsImage
                self.isLoading = false; self.request = nil
            }
        }
    }

    func cancel() { load(nil) }
}
