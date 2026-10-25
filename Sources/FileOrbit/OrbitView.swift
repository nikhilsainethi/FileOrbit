import SwiftUI
import AppKit
import UniformTypeIdentifiers
import FileOrbitCore
import PDFKit

struct OrbitView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var preferences = StudioPreferences.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var showsDependency = false
    @StateObject private var dropSession = OrbitDropSession()
    @FocusState private var focused: Bool
    private var spring: Animation? { reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.72) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if model.input != nil {
                radialContent
                    .scaleEffect(model.stage == .working && !model.neuralBusy ? 0.12 : 1, anchor: UnitPoint(x: OrbitLayout.center.x / OrbitLayout.canvasSize.width, y: OrbitLayout.center.y / OrbitLayout.canvasSize.height))
                    .opacity(model.stage == .working && !model.neuralBusy ? 0 : 1)
                    .animation(spring, value: model.stage)
            } else { welcome }
            if let hint = model.dependencyHint {
                Button { showsDependency.toggle() } label: {
                    Image(systemName: "info").font(.system(size: 11, weight: .semibold)).frame(width: 28, height: 28)
                        .modifier(LiquidGlassStyle(shape: Circle()))
                }.buttonStyle(.plain).help(hint).accessibilityLabel("Available converters")
                    .position(x: OrbitLayout.closeFrame.midX - 36, y: OrbitLayout.closeFrame.midY)
                    .popover(isPresented: $showsDependency) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(hint).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                            Button("Converter settings") { showsDependency = false; model.onSettings?() }
                        }.padding(16).frame(width: 260)
                    }
            }
            Button { model.onDismiss?() } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).frame(width: 28, height: 28)
                    .modifier(LiquidGlassStyle(shape: Circle()))
            }
            .buttonStyle(.plain).help("Close · Escape").accessibilityLabel("Close FileOrbit")
            .position(x: OrbitLayout.closeFrame.midX, y: OrbitLayout.closeFrame.midY)
            .opacity(model.stage == .working && !model.neuralBusy ? 0 : 1)
        }
        .frame(width: OrbitLayout.canvasSize.width, height: OrbitLayout.canvasSize.height)
        .foregroundStyle(OrbitPalette.primaryText(for: scheme))
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let point): model.hover(CGPoint(x: point.x - OrbitLayout.wheelFrame.minX, y: point.y - OrbitLayout.wheelFrame.minY))
            case .ended: model.hover(nil)
            }
        }
        .onDrop(of: [UTType.fileURL.identifier], delegate: OrbitFileDropDelegate(model: model, session: dropSession))
        .focusable().focusEffectDisabled().focused($focused)
        .onAppear { focused = true }
        .onChange(of: model.input) { focused = true }
        .onKeyPress(.leftArrow) { model.keyboardMove(-1); return .handled }
        .onKeyPress(.upArrow) { model.keyboardMove(-1); return .handled }
        .onKeyPress(.rightArrow) { model.keyboardMove(1); return .handled }
        .onKeyPress(.downArrow) { model.keyboardMove(1); return .handled }
        .onKeyPress(.return) { model.keyboardActivate(); return .handled }
        .onExitCommand {
            if model.parameterParentID != nil { model.parameterParentID = nil; model.selectedParameterID = nil }
            else { model.onDismiss?() }
        }
        .alert("FileOrbit", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var radialContent: some View {
        ZStack(alignment: .topLeading) {
            ZStack {
                ForEach(Array(model.orbitActions.enumerated()), id: \.element.id) { index, action in
                    let angle = OrbitLayout.angle(index: index, count: model.orbitActions.count, compressionLast: model.compressionLast)
                    OrbitActionSector(action: action, angle: angle, span: OrbitLayout.span(count: model.orbitActions.count), active: model.selectedActionID == action.id) { model.activate(action) }
                }
                if let layout = model.parameterLayout {
                    ForEach(Array(model.parameters.enumerated()), id: \.element.id) { index, parameter in
                        OrbitParameterSector(parameter: parameter, shape: layout.shape(index), angle: layout.angle(index), active: model.selectedParameterID == parameter.id) { model.execute(parameter.command) }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
                }
            }
            .id(model.mode)
            .transition(.modifier(active: OrbitModeTransition(angle: -10, opacity: 0), identity: OrbitModeTransition(angle: 0, opacity: 1)))
            .frame(width: OrbitLayout.wheelFrame.width, height: OrbitLayout.wheelFrame.height)
            .position(x: OrbitLayout.wheelFrame.midX, y: OrbitLayout.wheelFrame.midY)
            .animation(spring, value: model.mode)
            .animation(spring, value: model.selectedActionID)
            .animation(spring, value: model.selectedParameterID)
            .animation(spring, value: model.parameterParentID)
            OrbitLoupeHub(model: model)
                .frame(width: 104, height: 104)
                .position(x: OrbitLayout.center.x, y: OrbitLayout.center.y)
            if model.orbitActions.isEmpty {
                VStack(spacing: 7) {
                    Text(model.dependencyHint ?? "No \(model.mode.title.lowercased()) tools for this file. Try another mode.")
                        .font(.system(size: 10)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    Button("Settings") { model.onSettings?() }.buttonStyle(.plain).font(.system(size: 10, weight: .semibold))
                }.padding(12).frame(width: 240)
                    .modifier(LiquidGlassStyle(shape: RoundedRectangle(cornerRadius: 16)))
                    .position(x: OrbitLayout.center.x, y: OrbitLayout.center.y + 110)
            }
            modeLegend
        }
        .frame(width: OrbitLayout.canvasSize.width, height: OrbitLayout.canvasSize.height)
    }
    private var modeLegend: some View {
        let frame = model.parameters.isEmpty ? OrbitLayout.captionFrame : OrbitLayout.expandedCaptionFrame
        return HStack(spacing: 0) {
            ForEach(OrbitMode.allCases) { mode in
                Button { model.setMode(mode) } label: {
                    HStack(spacing: 4) {
                        Text(mode.key).font(.system(size: 12, weight: .medium))
                        Text(mode.title).font(.system(size: 9, weight: model.mode == mode ? .bold : .medium))
                    }
                    .foregroundStyle(model.mode == mode ? OrbitPalette.activeText(for: scheme) : OrbitPalette.secondaryText(for: scheme))
                    .frame(maxWidth: .infinity).frame(height: 26)
                    .background { if model.mode == mode { Capsule().fill(OrbitPalette.accent(for: scheme).opacity(0.13)).padding(3) } }
                }
                .buttonStyle(.plain).accessibilityLabel(mode.title + " mode")
            }
        }
        .frame(width: frame.width, height: 26)
        .modifier(LiquidGlassStyle(shape: Capsule()))
        .position(x: frame.midX, y: frame.midY)
        .animation(spring, value: model.parameterParentID)
    }
    private var welcome: some View {
        VStack(spacing: 14) {
            Image(systemName: "circle.hexagongrid").font(.system(size: 36, weight: .light)).symbolRenderingMode(.hierarchical)
                .foregroundStyle(OrbitPalette.accent(for: scheme))
            Text("At your fingertips.").font(.system(size: 23, weight: .semibold, design: .rounded))
            Text(FileOrbitRuntime.isPreview ? "Open a sample to explore the new wheel.\nThe installed shortcut stays with FileOrbit." : "Select a file in Finder.\nDouble-tap ⌘ to see its actions.")
                .font(.system(size: 12)).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Choose files…") { model.chooseFile() }.buttonStyle(.borderedProminent).tint(OrbitPalette.accent(for: scheme))
            HStack {
                Button("Glass Shelf") { model.onShelf?([]) }
                Button("Settings") { model.onSettings?() }
            }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
            Text("Everything stays on your Mac.").font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(26).frame(width: 320, height: 290)
        .modifier(LiquidGlassStyle(shape: RoundedRectangle(cornerRadius: 32)))
        .position(x: OrbitLayout.center.x, y: OrbitLayout.center.y)
    }
}

private struct OrbitLoupeHub: View {
    @ObservedObject var model: AppModel
    var body: some View { OrbitLoupeOverlay(model: model, loupe: model.loupe) }
}
private struct OrbitLoupeOverlay: View {
    @ObservedObject var model: AppModel
    @ObservedObject var loupe: SplitLoupeModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            OrbitHub(model: model, inspector: model.inspector).frame(width: 104, height: 104)
            if model.neuralBusy { NeuralHubShimmer().frame(width: 104, height: 104) }
            if loupe.isVisible { SplitLoupePreviewView(model: loupe).transition(.scale(scale: 0.4).combined(with: .opacity)) }
        }.animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: loupe.isVisible)
    }
}
private struct OrbitModeTransition: ViewModifier {
    let angle: Double
    let opacity: Double
    func body(content: Content) -> some View { content.rotationEffect(.degrees(angle)).opacity(opacity) }
}
private struct OrbitActionSector: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let action: OrbitAction
    let angle: Double
    let span: Double
    let active: Bool
    let perform: () -> Void
    var body: some View {
        let shape = AnnularWedgeShape(centerAngle: angle, span: span)
        let point = OrbitLayout.polar(radius: OrbitLayout.labelRadius, degrees: angle, center: OrbitLayout.wheelCenter)
        let offset = OrbitLayout.polar(radius: active ? 6 : 0, degrees: angle, center: .zero)
        Button(action: perform) {
            ZStack {
                Color.clear
                VStack(spacing: 5) {
                    Image(systemName: action.symbol).font(.system(size: 17, weight: .medium)).symbolRenderingMode(.hierarchical)
                        .symbolEffect(.bounce, options: .nonRepeating, isActive: active && !reduceMotion)
                    Text(action.title).font(.system(size: action.title.count > 8 ? 8.5 : 10, weight: active ? .bold : .semibold))
                        .lineLimit(action.title.contains(" ") ? 2 : 1).minimumScaleFactor(0.8)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: max(58, min(78, CGFloat(span) * 1.1)))
                .foregroundStyle(active ? OrbitPalette.activeText(for: scheme) : OrbitPalette.primaryText(for: scheme))
                .position(point)
            }
            .frame(width: 384, height: 384)
            .modifier(LiquidGlassStyle(shape: shape, active: active)).contentShape(shape)
        }
        .buttonStyle(.plain).scaleEffect(active ? 1.03 : 1).offset(x: offset.x, y: offset.y)
        .accessibilityLabel(action.title).accessibilityHint(action.subtitle).help(action.subtitle)
    }
}
private struct OrbitParameterSector: View {
    @Environment(\.colorScheme) private var scheme
    let parameter: OrbitParameter
    let shape: AnnularWedgeShape
    let angle: Double
    let active: Bool
    let perform: () -> Void
    private var tangentRotation: Double {
        let value = (angle + 90).truncatingRemainder(dividingBy: 180)
        return value > 90 ? value - 180 : value < -90 ? value + 180 : value
    }
    var body: some View {
        let point = OrbitLayout.polar(radius: OrbitLayout.secondaryLabelRadius, degrees: angle, center: OrbitLayout.wheelCenter)
        let offset = OrbitLayout.polar(radius: active ? 6 : 0, degrees: angle, center: .zero)
        Button(action: perform) {
            ZStack {
                Color.clear
                VStack(spacing: 2) {
                    Text(parameter.title).font(.system(size: 10, weight: .bold))
                    Text(parameter.subtitle).font(.system(size: 7.5, weight: .medium))
                }.lineLimit(1).frame(width: 94, height: 28)
                    .rotationEffect(.degrees(tangentRotation))
                    .foregroundStyle(active ? OrbitPalette.activeText(for: scheme) : OrbitPalette.primaryText(for: scheme))
                    .position(point)
            }.frame(width: 384, height: 384)
                .modifier(LiquidGlassStyle(shape: shape, active: active)).contentShape(shape)
        }
        .buttonStyle(.plain).scaleEffect(active ? 1.03 : 1).offset(x: offset.x, y: offset.y)
        .accessibilityLabel(parameter.title + ", " + parameter.subtitle)
    }
}
private struct OrbitHub: View {
    @ObservedObject var model: AppModel
    @ObservedObject var inspector: FileInspector
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Button { if let input = model.input { model.onShelf?([input]) } } label: {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(.white.opacity(scheme == .dark ? 0.08 : 0.48))
                    if let image = inspector.thumbnail { Image(nsImage: image).resizable().scaledToFit().padding(3) }
                    else { Image(systemName: "doc").font(.system(size: 21)).foregroundStyle(.secondary) }
                }.frame(width: 34, height: 36)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.35), lineWidth: 1))
                Text(model.input?.lastPathComponent ?? "FileOrbit").font(.system(size: 9.5, weight: .semibold))
                    .lineLimit(1).truncationMode(.middle).frame(width: 88)
                Text(model.prediction ?? inspector.metadataText)
                    .font(.system(size: 8, weight: .medium)).lineLimit(2).multilineTextAlignment(.center)
                    .foregroundStyle(model.prediction == nil ? OrbitPalette.secondaryText(for: scheme) : OrbitPalette.activeText(for: scheme))
                    .frame(width: 88, height: 22).id(model.prediction ?? inspector.metadataText)
                    .transition(.opacity).animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: model.prediction)
            }
            .frame(width: 104, height: 104)
            .modifier(LiquidGlassStyle(shape: Circle(), active: model.isDraggingFile))
            .contentShape(Circle())
        }.buttonStyle(.plain).help("Open Glass Shelf · drop files here to collect them")
            .accessibilityLabel("File inspector: " + (model.input?.lastPathComponent ?? "No file") + ", " + inspector.metadataText)
            .accessibilityHint("Opens the batch shelf")
    }
}

@MainActor final class OrbitDropSession: ObservableObject {
    var urls: [URL] = []
    var generation = UUID()
    var entered = false
    static func pasteboardURLs() -> [URL] {
        (NSPasteboard(name: .drag).readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }
    static func load(_ providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            let url: URL? = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
            }
            if let url, url.isFileURL { urls.append(url) }
        }
        return urls
    }
}
private struct OrbitFileDropDelegate: DropDelegate {
    let model: AppModel
    let session: OrbitDropSession
    func validateDrop(info: DropInfo) -> Bool { model.stage != .working && info.hasItemsConforming(to: [UTType.fileURL.identifier]) }
    func dropEntered(info: DropInfo) {
        session.entered = true; session.generation = UUID(); session.urls = OrbitDropSession.pasteboardURLs()
        model.isDraggingFile = true
        if let first = session.urls.first, first != model.input { model.select(first) }
        if session.urls.isEmpty {
            let generation = session.generation, providers = info.itemProviders(for: [UTType.fileURL.identifier])
            Task { @MainActor in
                let urls = await OrbitDropSession.load(providers)
                guard session.entered, session.generation == generation else { return }
                session.urls = urls
                if let first = urls.first, first != model.input { model.select(first) }
            }
        }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        model.updateModifiers(NSEvent.modifierFlags)
        let point = CGPoint(x: info.location.x - OrbitLayout.wheelFrame.minX, y: info.location.y - OrbitLayout.wheelFrame.minY)
        model.hover(point)
        return DropProposal(operation: model.acceptsDrop(at: point) ? .copy : .forbidden)
    }
    func dropExited(info: DropInfo) { session.entered = false; model.isDraggingFile = false; model.hover(nil) }
    func performDrop(info: DropInfo) -> Bool {
        let point = CGPoint(x: info.location.x - OrbitLayout.wheelFrame.minX, y: info.location.y - OrbitLayout.wheelFrame.minY)
        guard model.acceptsDrop(at: point) else { session.entered = false; model.isDraggingFile = false; return false }
        let urls = session.urls
        session.entered = false; model.isDraggingFile = false
        if !urls.isEmpty { model.drop(urls, at: point) }
        else {
            let providers = info.itemProviders(for: [UTType.fileURL.identifier])
            Task { @MainActor in
                let loaded = await OrbitDropSession.load(providers)
                // No synchronous selection was available: collect safely in the shelf.
                if !loaded.isEmpty { model.onShelf?(loaded) }
            }
        }
        return true
    }
}

#if FILEORBIT_XCODE_PREVIEWS
#Preview("Optical Daylight Quartz") { OrbitPreviewScene().preferredColorScheme(.light) }
#Preview("Smoked Obsidian Crystal") { OrbitPreviewScene().preferredColorScheme(.dark) }
@MainActor private struct OrbitPreviewScene: View {
    @StateObject private var model = OrbitPreviewScene.makeModel()
    var body: some View { OrbitView(model: model) }
    private static func makeModel() -> AppModel {
        let model = AppModel()
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("FileOrbit-preview-" + UUID().uuidString + ".pdf")
        let document = PDFDocument()
        for index in 0..<2 {
            let image = NSImage(size: NSSize(width: 300, height: 400), flipped: false) { rect in
                NSColor(calibratedRed: 0.10, green: 0.45, blue: 0.48, alpha: 1).setFill(); rect.fill()
                ("Design study · \(index + 1)" as NSString).draw(at: NSPoint(x: 24, y: 200), withAttributes: [.font: NSFont.systemFont(ofSize: 22, weight: .bold), .foregroundColor: NSColor.white])
                return true
            }
            if let page = PDFPage(image: image) { document.insert(page, at: index) }
        }
        if document.write(to: source) { model.select(source); model.selectedActionID = "convert-png"; model.parameterParentID = "convert-png" }
        return model
    }
}
#endif
