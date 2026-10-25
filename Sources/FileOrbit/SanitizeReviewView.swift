import AppKit
import SwiftUI
import Combine
import FileOrbitCore

@MainActor final class SanitizeReviewModel: ObservableObject {
    let input: URL
    let outputDirectory: URL?
    @Published private(set) var document: SanitizeDocument?
    @Published private(set) var regions: [PrivacyDetection] = []
    @Published private(set) var pageIndex = 0
    @Published private(set) var image: NSImage?
    @Published private(set) var isInspecting = false
    @Published private(set) var isExporting = false
    @Published var style: SanitizeStyle
    @Published var reviewed = false
    @Published var error: String?
    private let engine = NeuralProcessingActor()
    private var token = CancellationToken()
    private var generation = UUID()
    private var active = true

    init(input: URL, style: SanitizeStyle = .obsidian, outputDirectory: URL? = nil, autoLoad: Bool = true) {
        self.input = input; self.style = style; self.outputDirectory = outputDirectory
        if autoLoad { inspect() }
    }
    var pageCount: Int { document?.pages.count ?? 0 }
    var currentRegions: [PrivacyDetection] { regions.filter { $0.region.pageIndex == pageIndex } }
    var canExport: Bool { active && document != nil && reviewed && !isInspecting && !isExporting }

    func inspect() {
        guard active, !isInspecting, !isExporting else { return }
        token.cancel(); token = CancellationToken(); generation = UUID()
        let requestID = generation, cancellation = token, actor = engine, input = input
        isInspecting = true; document = nil; image = nil; regions = []; reviewed = false; error = nil
        Task { [weak self] in
            do {
                let result = try await actor.inspect(input: input, cancellation: cancellation)
                guard let self, self.active, self.generation == requestID else { return }
                self.document = result; self.regions = result.detections; self.showPage(0); self.isInspecting = false
            } catch {
                guard let self, self.active, self.generation == requestID else { return }
                self.isInspecting = false; self.error = error.localizedDescription
            }
        }
    }
    func showPage(_ index: Int) {
        guard !isExporting, let document, document.pages.indices.contains(index) else { return }
        pageIndex = index; image = NSImage(data: document.pages[index].pngData)
    }
    func add(_ rect: CGRect) {
        guard !isExporting, document != nil, regions.count < 10_000,
              [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite), rect.minX >= 0, rect.minY >= 0,
              rect.maxX <= 1, rect.maxY <= 1, rect.width > 0, rect.height > 0 else { return }
        regions.append(.init(kind: .manual, region: .init(pageIndex: pageIndex, normalizedRect: rect)))
    }
    func remove(_ id: UUID) { guard !isExporting else { return }; regions.removeAll { $0.id == id } }
    func clearPage() { guard !isExporting else { return }; regions.removeAll { $0.region.pageIndex == pageIndex } }
    func export(_ completion: @escaping @MainActor (URL, ConversionResult) -> Void) {
        guard canExport, let document else { return }
        isExporting = true; error = nil
        let requestID = generation, cancellation = token, actor = engine, style = style, directory = outputDirectory
        let selected = regions.map(\.region)
        Task { [weak self] in
            do {
                let result = try await actor.sanitize(document: document, regions: selected, style: style, outputDirectory: directory, cancellation: cancellation)
                // Atomic publication wins a late Cancel. Always report a successfully saved copy.
                if let self, self.generation == requestID { self.isExporting = false }
                completion(document.input, result)
            } catch {
                guard let self, self.active, self.generation == requestID else { return }
                self.isExporting = false; self.error = error.localizedDescription
            }
        }
    }
    func cancel() {
        token.cancel(); generation = UUID(); active = false; isInspecting = false; isExporting = false
        document = nil; image = nil; regions = []; reviewed = false
    }
}

struct SanitizeReviewView: View {
    @ObservedObject var model: SanitizeReviewModel
    var onCompleted: @MainActor (URL, ConversionResult) -> Void
    var onCancel: @MainActor () -> Void
    var exportTitle = "Save reviewed copy"
    @Environment(\.colorScheme) private var scheme
    @State private var draft: CGRect?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Sanitize · review a copy", systemImage: "checkmark.shield").font(.title3.weight(.semibold))
                    Text(model.input.lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button("Cancel") { model.cancel(); onCancel() }.keyboardShortcut(.cancelAction)
                Button(model.isExporting ? "Saving…" : exportTitle) { model.export(onCompleted) }
                    .buttonStyle(.borderedProminent).disabled(!model.canExport)
            }.padding(18)
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "eye").foregroundStyle(OrbitPalette.accent(for: scheme))
                Text("Detection can miss information. Review every page, remove incorrect boxes, and draw over anything else to remove. Selected pixels are permanently replaced in the copy.")
                    .font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
            }.padding(.horizontal, 18).padding(.bottom, 12)
            HStack {
                Picker("Replacement", selection: $model.style) { ForEach(SanitizeStyle.allCases, id: \.self) { Text($0.title).tag($0) } }
                    .pickerStyle(.segmented).frame(maxWidth: 340).disabled(model.isExporting)
                Spacer()
                Text("\(model.regions.count) selected \(model.regions.count == 1 ? "region" : "regions")").font(.caption).monospacedDigit()
            }.padding(.horizontal, 18).padding(.bottom, 12)
            Divider()
            GeometryReader { geometry in
                ZStack {
                    Color(NSColor.underPageBackgroundColor).opacity(0.6)
                    if let image = model.image {
                        let available = CGSize(width: max(1, geometry.size.width - 44), height: max(1, geometry.size.height - 32))
                        let scale = min(available.width / image.size.width, available.height / image.size.height)
                        page(image, size: CGSize(width: image.size.width * scale, height: image.size.height * scale))
                            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    } else if model.isInspecting {
                        VStack(spacing: 12) { ProgressView(); Text("Finding private information on this Mac…").font(.callout); Text("Nothing leaves this Mac.").font(.caption).foregroundStyle(.secondary) }
                    } else {
                        ContentUnavailableView("Review not ready", systemImage: "doc.text.magnifyingglass", description: Text(model.error ?? "Choose an image or PDF to inspect."))
                    }
                    if model.isExporting { Color.black.opacity(0.16); ProgressView("Replacing pixels and verifying the original…").padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) }
                }
            }
            Divider()
            HStack(spacing: 10) {
                Button { model.showPage(model.pageIndex - 1); draft = nil } label: { Image(systemName: "chevron.left") }
                    .disabled(model.pageIndex == 0 || model.isExporting).help("Previous page")
                Text("Page \(model.pageCount == 0 ? 0 : model.pageIndex + 1) of \(model.pageCount)").font(.caption).monospacedDigit()
                Button { model.showPage(model.pageIndex + 1); draft = nil } label: { Image(systemName: "chevron.right") }
                    .disabled(model.pageIndex + 1 >= model.pageCount || model.isExporting).help("Next page")
                Spacer()
                Button("Clear this page") { model.clearPage() }.disabled(model.currentRegions.isEmpty || model.isExporting)
            }.padding(.horizontal, 18).padding(.top, 12)
            VStack(alignment: .leading, spacing: 6) {
                Toggle("I reviewed every page and selected all content I want removed", isOn: $model.reviewed)
                    .toggleStyle(.checkbox).font(.system(size: 12)).disabled(model.document == nil || model.isExporting)
                Text(model.document?.isPDF == true
                     ? "Every PDF page is rebuilt as pixels. Searchable text, vectors, forms, attachments and original metadata are removed."
                     : "Original EXIF, GPS and XMP metadata are removed. Images are processed at up to 4,096 pixels per side.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if model.regions.isEmpty, model.document != nil { Text("No boxes selected: export removes metadata only. Visible private information may remain.").font(.system(size: 10, weight: .medium)).foregroundStyle(.orange) }
                if let error = model.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            }.padding(18)
        }
        .foregroundStyle(OrbitPalette.primaryText(for: scheme))
        .tint(OrbitPalette.accent(for: scheme))
        .modifier(LiquidGlassStyle(shape: RoundedRectangle(cornerRadius: 18)))
        .frame(minWidth: 650, minHeight: 610)
    }
    private func page(_ image: NSImage, size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Image(nsImage: image).resizable().frame(width: size.width, height: size.height)
                .accessibilityLabel("Review page \(model.pageIndex + 1). Drag to add a redaction rectangle.")
            ForEach(model.currentRegions) { detection in
                let r = detection.region.normalizedRect
                Rectangle().fill(model.style == .obsidian ? Color.black : Color(red: 0.78, green: 0.88, blue: 0.89))
                    .overlay(Rectangle().stroke(Color.teal, lineWidth: 1))
                    .frame(width: r.width * size.width, height: r.height * size.height)
                    .overlay(alignment: .topTrailing) {
                        Button { model.remove(detection.id) } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(.white, .black) }
                            .buttonStyle(.plain).offset(x: 5, y: -5).help("Remove \(detection.kind.title.lowercased()) box")
                            .accessibilityLabel("Remove \(detection.kind.title.lowercased()) box").disabled(model.isExporting)
                    }
                    .help(detection.kind.title)
                    .position(x: r.midX * size.width, y: r.midY * size.height)
            }
            if let draft {
                Rectangle().fill(.teal.opacity(0.35)).overlay(Rectangle().stroke(.teal, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    .frame(width: draft.width * size.width, height: draft.height * size.height)
                    .position(x: draft.midX * size.width, y: draft.midY * size.height).allowsHitTesting(false)
            }
        }
        .frame(width: size.width, height: size.height).background(.white).shadow(color: .black.opacity(0.14), radius: 8, y: 3)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 4).onChanged { gesture in
            guard !model.isExporting else { return }
            draft = RedactionSelection.normalized(from: gesture.startLocation, to: gesture.location, size: size)
        }.onEnded { gesture in
            if let rect = RedactionSelection.normalized(from: gesture.startLocation, to: gesture.location, size: size) { model.add(rect) }
            draft = nil
        })
    }
}

#if FILEORBIT_XCODE_PREVIEWS
#Preview("Sanitize Review · Daylight") {
    if let assets = try? OnboardingSandboxAssets.create() {
        SanitizeReviewView(model: SanitizeReviewModel(input: assets.deck, style: .frosted, outputDirectory: assets.outputDirectory), onCompleted: { _, _ in }, onCancel: {})
            .frame(width: 760, height: 730).preferredColorScheme(.light)
    }
}
#Preview("Sanitize Review · Obsidian") {
    if let assets = try? OnboardingSandboxAssets.create() {
        SanitizeReviewView(model: SanitizeReviewModel(input: assets.deck, outputDirectory: assets.outputDirectory), onCompleted: { _, _ in }, onCancel: {})
            .frame(width: 760, height: 730).preferredColorScheme(.dark)
    }
}
#endif
