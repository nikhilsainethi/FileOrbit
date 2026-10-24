import SwiftUI
import AppKit
import PDFKit
import CryptoKit
import FileOrbitCore

enum RedactionSelection {
    static func normalized(from start: CGPoint, to end: CGPoint, size: CGSize) -> CGRect? {
        guard [start.x, start.y, end.x, end.y, size.width, size.height].allSatisfy(\.isFinite), size.width > 0, size.height > 0 else { return nil }
        func clamp(_ point: CGPoint) -> CGPoint { CGPoint(x: min(size.width, max(0, point.x)), y: min(size.height, max(0, point.y))) }
        let a = clamp(start), b = clamp(end)
        guard abs(a.x - b.x) >= 4, abs(a.y - b.y) >= 4 else { return nil }
        return CGRect(x: min(a.x, b.x) / size.width, y: min(a.y, b.y) / size.height,
                      width: abs(a.x - b.x) / size.width, height: abs(a.y - b.y) / size.height)
    }
}
@MainActor final class RedactionEditorModel: ObservableObject {
    struct Region: Identifiable { let id = UUID(); let value: RedactionRegion }
    let input: URL
    @Published private(set) var pageCount = 0
    @Published private(set) var pageIndex = 0
    @Published private(set) var image: NSImage?
    @Published private(set) var regions: [Region] = []
    @Published private(set) var isLoading = true
    @Published private(set) var isVerifying = false
    @Published var error: String?
    private var sourceDigest: Data?
    private var document: PDFDocument?
    private var generation = UUID()
    private var lifecycle = UUID()
    private var active = true
    init(input: URL) { self.input = input; load() }
    private func load() {
        Task { [weak self, input] in
            let outcome = await Task.detached(priority: .userInitiated) { () -> Result<(Data, Data), Error> in
                Result {
                    let values = try input.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
                    guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? 0) <= 1_073_741_824 else {
                        throw ConversionError.invalidInput("Choose a regular PDF no larger than 1 GB.")
                    }
                    let data = try Data(contentsOf: input, options: .mappedIfSafe)
                    return (data, Data(SHA256.hash(data: data)))
                }
            }.value
            guard let self, self.active else { return }
            switch outcome {
            case .success(let (data, digest)):
                guard let document = PDFDocument(data: data), !document.isLocked, document.pageCount > 0 else {
                    self.error = "This PDF cannot be opened for redaction. Unlock a separate copy first."; self.isLoading = false; return
                }
                self.document = document; self.sourceDigest = digest; self.pageCount = document.pageCount; self.showPage(0)
            case .failure(let error): self.error = error.localizedDescription; self.isLoading = false
            }
        }
    }
    func showPage(_ index: Int) {
        guard active, let document, (0..<document.pageCount).contains(index), let page = document.page(at: index) else { return }
        pageIndex = index; image = nil; isLoading = true
        let id = UUID(); generation = id
        Task { [weak self] in
            let thumbnail = await Task.detached(priority: .userInitiated) {
                page.thumbnail(of: NSSize(width: 1200, height: 1200), for: .cropBox)
            }.value
            guard let self, self.active, self.generation == id else { return }
            self.image = thumbnail; self.isLoading = false
        }
    }
    func add(_ rectangle: CGRect) { guard active else { return }; regions.append(Region(value: RedactionRegion(pageIndex: pageIndex, normalizedRect: rectangle))) }
    func remove(_ id: UUID) { regions.removeAll { $0.id == id } }
    func clearPage() { regions.removeAll { $0.value.pageIndex == pageIndex } }
    func cancel() {
        active = false; lifecycle = UUID(); generation = UUID(); isVerifying = false; isLoading = false
        document = nil; image = nil
    }
    func export(_ action: @escaping ([RedactionRegion]) -> Void) {
        guard active, !regions.isEmpty, let sourceDigest, !isVerifying else { return }
        let requestLifecycle = lifecycle
        isVerifying = true
        Task { [weak self, input] in
            let actual = await Task.detached(priority: .userInitiated) { try? Data(SHA256.hash(data: Data(contentsOf: input, options: .mappedIfSafe))) }.value
            guard let self, self.active, self.lifecycle == requestLifecycle else { return }
            self.isVerifying = false
            guard actual == sourceDigest else {
                self.error = "The original PDF changed after this preview opened. Reopen it and mark the regions again before exporting."; return
            }
            action(self.regions.map(\.value))
        }
    }
}
struct RedactionEditorView: View {
    @ObservedObject var model: RedactionEditorModel
    var onExport: ([RedactionRegion]) -> Void
    var onCancel: () -> Void
    @State private var draft: CGRect?
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Redact a copy").font(.title3.weight(.semibold))
                    Text(model.input.lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button(model.isVerifying ? "Checking original…" : "Save redacted copy") { model.export(onExport) }
                    .buttonStyle(.borderedProminent).disabled(model.regions.isEmpty || model.isVerifying || model.isLoading)
            }.padding(18)
            HStack(spacing: 8) {
                Image(systemName: "rectangle.dashed.badge.record")
                Text("Drag rectangles over the content to remove. Export flattens every page; searchable text and vector content are removed.")
                    .font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
            }.foregroundStyle(.secondary).padding(.horizontal, 18).padding(.bottom, 12)
            Divider()
            GeometryReader { proxy in
                ZStack {
                    Color(NSColor.underPageBackgroundColor)
                    if let image = model.image {
                        let available = CGSize(width: max(1, proxy.size.width - 40), height: max(1, proxy.size.height - 30))
                        let scale = min(available.width / image.size.width, available.height / image.size.height)
                        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                        page(image, size: size).position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    } else if model.isLoading { ProgressView("Loading page…") }
                    else { ContentUnavailableView("Preview unavailable", systemImage: "doc.badge.ellipsis", description: Text(model.error ?? "This page cannot be displayed.")) }
                }
            }
            Divider()
            HStack {
                Button { model.showPage(model.pageIndex - 1); draft = nil } label: { Image(systemName: "chevron.left") }.disabled(model.pageIndex == 0 || model.isLoading)
                Text("Page \(model.pageCount == 0 ? 0 : model.pageIndex + 1) of \(model.pageCount)").font(.system(size: 12, weight: .medium)).monospacedDigit()
                Button { model.showPage(model.pageIndex + 1); draft = nil } label: { Image(systemName: "chevron.right") }.disabled(model.pageIndex + 1 >= model.pageCount || model.isLoading)
                Spacer()
                Text("\(model.regions.count) region\(model.regions.count == 1 ? "" : "s") marked").font(.caption).foregroundStyle(.secondary)
                Button("Clear this page") { model.clearPage() }.disabled(!model.regions.contains { $0.value.pageIndex == model.pageIndex })
            }.padding(14)
        }.frame(minWidth: 650, minHeight: 580)
            .alert("Redaction", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("OK") { model.error = nil }
            } message: { Text(model.error ?? "") }
    }
    private func page(_ image: NSImage, size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Image(nsImage: image).resizable().frame(width: size.width, height: size.height)
                .accessibilityLabel("Page \(model.pageIndex + 1). Draw a rectangle to mark content for removal.")
            ForEach(model.regions.filter { $0.value.pageIndex == model.pageIndex }) { region in
                let rect = region.value.normalizedRect
                Rectangle().fill(.black.opacity(0.88)).overlay(Rectangle().stroke(.cyan.opacity(0.8), lineWidth: 1))
                    .frame(width: rect.width * size.width, height: rect.height * size.height)
                    .overlay(alignment: .topTrailing) {
                        Button { model.remove(region.id) } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 13)).foregroundStyle(.white, .black) }
                            .buttonStyle(.plain).offset(x: 5, y: -5).help("Remove this region").accessibilityLabel("Remove redaction region")
                    }
                    .position(x: rect.midX * size.width, y: rect.midY * size.height)
            }
            if let draft {
                Rectangle().fill(.black.opacity(0.55)).overlay(Rectangle().stroke(.cyan, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    .frame(width: draft.width * size.width, height: draft.height * size.height)
                    .position(x: draft.midX * size.width, y: draft.midY * size.height).allowsHitTesting(false)
            }
        }
        .frame(width: size.width, height: size.height).background(.white).shadow(color: .black.opacity(0.15), radius: 8, y: 3)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 4).onChanged { drag in
            draft = RedactionSelection.normalized(from: drag.startLocation, to: drag.location, size: size)
        }.onEnded { drag in
            if let rectangle = RedactionSelection.normalized(from: drag.startLocation, to: drag.location, size: size) { model.add(rectangle) }
            draft = nil
        })
    }
}
