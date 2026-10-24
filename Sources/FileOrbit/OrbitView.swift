import SwiftUI
import AppKit
import UniformTypeIdentifiers
import FileOrbitCore

private let orbitAccent = Color(red: 0.08, green: 0.57, blue: 0.53)

/// Midnight and muted slate glass, adapted from the user's Coolors reference:
/// https://coolors.co/palettes/trending/dark
/// Strong surface tint keeps pale desktop backgrounds from washing controls gray.
private enum OrbitNight {
    static let surface = Color(red: 23 / 255, green: 39 / 255, blue: 57 / 255)
    static let selected = Color(red: 63 / 255, green: 71 / 255, blue: 94 / 255)
    static let accent = Color(red: 201 / 255, green: 216 / 255, blue: 235 / 255)
    static let text = Color(red: 232 / 255, green: 237 / 255, blue: 244 / 255)
    static let secondary = Color(red: 171 / 255, green: 185 / 255, blue: 204 / 255)
    static let buttonInk = Color(red: 14 / 255, green: 30 / 255, blue: 50 / 255)
}

struct OrbitView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var dropTarget = false
    @State private var selectedAction = 0
    @FocusState private var wheelFocused: Bool

    private var actions: [FileAction] {
        // A stable bottom position makes compression easy to find across file types.
        model.actions.filter { !isCompression($0) } + model.actions.filter(isCompression)
    }
    private var activeAction: FileAction? { actions.indices.contains(selectedAction) ? actions[selectedAction] : actions.first }
    private var hasCompression: Bool { actions.last.map(isCompression) ?? false }
    private var wheelAnimation: Animation? { reduceMotion ? nil : .easeOut(duration: 0.16) }
    private var accent: Color { colorScheme == .dark ? OrbitNight.accent : orbitAccent }
    private var primaryText: Color { colorScheme == .dark ? OrbitNight.text : .primary }
    private var secondaryText: Color { colorScheme == .dark ? OrbitNight.secondary : .secondary }
    private var buttonInk: Color { colorScheme == .dark ? OrbitNight.buttonInk : .white }

    var body: some View {
        ZStack(alignment: .topLeading) {
            stageContent
            if model.stage != .working {
                Button { model.onDismiss?() } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                        .frame(width: 28, height: 28).modifier(OrbitGlass(shape: Circle()))
                }
                .buttonStyle(.plain).help("Close · Esc").accessibilityLabel("Close FileOrbit")
                .position(x: OrbitLayout.closeFrame.midX, y: OrbitLayout.closeFrame.midY)
            }
        }
        .frame(width: OrbitLayout.canvasSize.width, height: OrbitLayout.canvasSize.height)
        .foregroundStyle(primaryText)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $dropTarget) { providers in
            guard model.stage != .working, providers.count == 1, let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { DispatchQueue.main.async { model.select(url) } }
            }
            return true
        }
        .alert("FileOrbit", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .onExitCommand {
            if model.stage == .compression { model.back() }
            else if model.stage != .working { model.onDismiss?() }
        }
        .onChange(of: model.input) { _, _ in selectedAction = 0; wheelFocused = true }
        .onChange(of: model.actions) { _, _ in selectedAction = min(selectedAction, max(0, actions.count - 1)) }
        .onChange(of: model.stage) { _, stage in if stage == .ready || stage == .compression { wheelFocused = true } }
    }

    @ViewBuilder private var stageContent: some View {
        switch model.stage {
        case .ready:
            if let input = model.input, !actions.isEmpty { readyWheel(input: input) }
            else { introduction }
        case .compression: compressionWheel
        case .working: working
        case .result: completion
        }
    }

    private func readyWheel(input: URL) -> some View {
        ZStack(alignment: .topLeading) {
            glassGroup {
                ZStack {
                    ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                        OrbitSegment(title: action.title, symbol: action.symbol,
                                     angle: OrbitLayout.angle(index: index, count: actions.count, compressionLast: hasCompression),
                                     span: OrbitLayout.span(count: actions.count), active: index == selectedAction) {
                            selectedAction = index; model.perform(action)
                        }
                        .help(action.subtitle)
                        .accessibilityLabel(action.title + ". " + action.subtitle)
                        .accessibilityAddTraits(index == selectedAction ? .isSelected : [])
                    }
                    fileHub(input: input)
                }
                .frame(width: 410, height: 410)
                .onContinuousHover { phase in
                    if case .active(let point) = phase,
                       let index = OrbitLayout.actionIndex(at: point, count: actions.count, compressionLast: hasCompression) {
                        selectedAction = index
                    }
                }
            }
            .position(x: OrbitLayout.wheelFrame.midX, y: OrbitLayout.wheelFrame.midY)
            .focusable().focusEffectDisabled().focused($wheelFocused)
            .onAppear { wheelFocused = true }
            .onKeyPress(.rightArrow) { moveSelection(1); return .handled }
            .onKeyPress(.leftArrow) { moveSelection(-1); return .handled }
            .onKeyPress(.downArrow) { moveSelection(1); return .handled }
            .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
            .onKeyPress(.return) { if let activeAction { model.perform(activeAction) }; return .handled }

            if let activeAction {
                HStack(spacing: 9) {
                    Text(isCompression(activeAction) ? "Make this file smaller" : "Convert to \(activeAction.title)")
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "return").font(.system(size: 10, weight: .medium)).foregroundStyle(secondaryText)
                }
                .frame(width: OrbitLayout.captionFrame.width, height: OrbitLayout.captionFrame.height)
                .modifier(OrbitGlass(shape: Capsule()))
                .position(x: OrbitLayout.captionFrame.midX, y: OrbitLayout.captionFrame.midY)
                .accessibilityHidden(true)
            }
        }
        .animation(wheelAnimation, value: selectedAction)
    }

    private func fileHub(input: URL) -> some View {
        VStack(spacing: 7) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: input.path)).resizable().interpolation(.high)
                .frame(width: 42, height: 42).accessibilityHidden(true)
            Text(input.lastPathComponent).font(.system(size: 12, weight: .semibold))
                .lineLimit(2).truncationMode(.middle).multilineTextAlignment(.center).frame(width: 134)
            Text(model.inputSize).font(.system(size: 10.5, weight: .medium)).foregroundStyle(secondaryText)
            if model.dependencyHint != nil {
                Button { model.onSettings?() } label: { Image(systemName: "info.circle").font(.system(size: 11)) }
                    .buttonStyle(.plain).foregroundStyle(secondaryText)
                    .help(model.dependencyHint ?? "Settings").accessibilityLabel(model.dependencyHint ?? "Settings")
            }
        }
        .frame(width: 166, height: 166)
        .modifier(OrbitGlass(shape: Circle()))
        .overlay { if dropTarget { Circle().strokeBorder(accent, lineWidth: 2) } }
        .help(input.lastPathComponent)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Selected file, \(input.lastPathComponent), \(model.inputSize)")
    }

    private var compressionWheel: some View {
        ZStack(alignment: .topLeading) {
            glassGroup {
                ZStack {
                    ForEach(Array(CompressionPreset.allCases.enumerated()), id: \.element) { index, preset in
                        OrbitSegment(title: preset.rawValue.capitalized, symbol: presetSymbol(preset),
                                     angle: OrbitLayout.angle(index: index, count: 3, compressionLast: false),
                                     span: OrbitLayout.span(count: 3), active: model.preset == preset) {
                            model.preset = preset
                        }
                        .help(presetDescription(preset))
                        .accessibilityLabel(preset.rawValue.capitalized + ". " + presetDescription(preset))
                        .accessibilityAddTraits(model.preset == preset ? .isSelected : [])
                    }
                    VStack(spacing: 9) {
                        Button { model.back() } label: {
                            Label("Back", systemImage: "arrow.left").font(.system(size: 10.5, weight: .medium))
                        }.buttonStyle(.plain).foregroundStyle(secondaryText).help("All actions · Esc")
                        Text(model.preset.rawValue.capitalized).font(.system(size: 13, weight: .semibold))
                        Button { model.run(.compress(model.preset)) } label: {
                            Text("Compress").font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 18).padding(.vertical, 9)
                                .foregroundStyle(buttonInk).background(accent, in: Capsule())
                        }.buttonStyle(.plain).accessibilityLabel("Compress file with \(model.preset.rawValue) preset")
                    }
                    .frame(width: 166, height: 166).modifier(OrbitGlass(shape: Circle()))
                }.frame(width: 410, height: 410)
            }
            .position(x: OrbitLayout.wheelFrame.midX, y: OrbitLayout.wheelFrame.midY)
            .focusable().focusEffectDisabled().focused($wheelFocused)
            .onAppear { wheelFocused = true }
            .onKeyPress(.rightArrow) { movePreset(1); return .handled }
            .onKeyPress(.leftArrow) { movePreset(-1); return .handled }
            .onKeyPress(.downArrow) { movePreset(1); return .handled }
            .onKeyPress(.upArrow) { movePreset(-1); return .handled }
            .onKeyPress(.return) { model.run(.compress(model.preset)); return .handled }

            Text(presetCaption(model.preset)).font(.system(size: 11, weight: .medium))
                .frame(width: OrbitLayout.captionFrame.width, height: OrbitLayout.captionFrame.height)
                .modifier(OrbitGlass(shape: Capsule()))
                .position(x: OrbitLayout.captionFrame.midX, y: OrbitLayout.captionFrame.midY)
                .help(presetDescription(model.preset) + " A separate copy is saved only if it is smaller. Your original stays intact.")
        }
        .animation(wheelAnimation, value: model.preset)
    }

    private var working: some View {
        VStack(spacing: 17) {
            ProgressView().tint(accent).controlSize(.large).frame(height: 35)
            VStack(spacing: 6) {
                Text(model.cancelling ? "Cancelling…" : "Working on your Mac")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Text(model.input?.lastPathComponent ?? "")
                    .font(.system(size: 11)).foregroundStyle(secondaryText).lineLimit(2)
                    .truncationMode(.middle).multilineTextAlignment(.center).frame(width: 210)
            }
            Text("Your original stays intact.").font(.system(size: 10.5)).foregroundStyle(secondaryText)
            Button(model.cancelling ? "Cancelling…" : "Cancel") { model.cancel() }
                .buttonStyle(.bordered).controlSize(.small).disabled(model.cancelling)
        }
        .frame(width: OrbitLayout.workingFrame.width, height: OrbitLayout.workingFrame.height)
        .modifier(OrbitGlass(shape: Circle()))
        .position(x: OrbitLayout.workingFrame.midX, y: OrbitLayout.workingFrame.midY)
    }

    private var completion: some View {
        VStack(spacing: 17) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 34, weight: .light))
                .foregroundStyle(accent).accessibilityHidden(true)
            Text("Your file is ready").font(.system(size: 22, weight: .semibold, design: .rounded))
            if let result = model.result {
                Text(result.outputURLs.count == 1 ? (result.outputURLs.first?.lastPathComponent ?? "File saved") : "\(result.outputURLs.count) files saved")
                    .font(.system(size: 12, weight: .medium)).lineLimit(2).truncationMode(.middle)
                    .multilineTextAlignment(.center).frame(maxWidth: 294)
                    .help(result.outputURLs.map(\.lastPathComponent).joined(separator: "\n"))
                HStack(spacing: 18) {
                    sizeColumn(title: "ORIGINAL", value: AppModel.bytes(result.inputBytes))
                    Image(systemName: "arrow.right").font(.system(size: 11)).foregroundStyle(secondaryText)
                    sizeColumn(title: "SAVED", value: AppModel.bytes(result.outputBytes))
                }
                if let note = result.note {
                    ScrollView { Text(note).font(.system(size: 11)).foregroundStyle(secondaryText)
                        .multilineTextAlignment(.center).frame(maxWidth: .infinity) }
                        .frame(maxHeight: 54)
                }
                Button { model.reveal() } label: {
                    Label("Show in Finder", systemImage: "folder").font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .foregroundStyle(buttonInk).background(accent, in: Capsule())
                }.buttonStyle(.plain)
                Button("Back to original file") { model.back() }.buttonStyle(.plain)
                    .font(.system(size: 11)).foregroundStyle(secondaryText)
            }
        }
        .padding(27)
        .frame(width: OrbitLayout.cardFrame.width, height: OrbitLayout.cardFrame.height)
        .modifier(OrbitGlass(shape: RoundedRectangle(cornerRadius: 32)))
        .position(x: OrbitLayout.cardFrame.midX, y: OrbitLayout.cardFrame.midY)
    }

    private var introduction: some View {
        VStack(spacing: 20) {
            Image(systemName: model.input == nil ? "circle.hexagongrid" : "doc.questionmark")
                .font(.system(size: 42, weight: .ultraLight)).foregroundStyle(accent)
                .accessibilityHidden(true)
            VStack(spacing: 10) {
                Text(model.input == nil ? "A little space for your files" : "No available actions")
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                if let input = model.input {
                    Text(input.lastPathComponent).font(.system(size: 12, weight: .medium))
                        .lineLimit(2).truncationMode(.middle).help(input.lastPathComponent)
                }
                Text(model.dependencyHint ?? (FileOrbitRuntime.isPreview
                     ? "Choose a sample file to explore the glass wheel. Everything runs locally."
                     : "Select a file in Finder, then tap ⌘ twice.\nConvert or compress, right where you are."))
                    .font(.system(size: 12)).foregroundStyle(secondaryText)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).lineSpacing(3)
            }
            Button { model.chooseFile() } label: {
                Label("Choose a file", systemImage: "plus").font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .foregroundStyle(buttonInk).background(accent, in: Capsule())
            }.buttonStyle(.plain)
            Button(model.input == nil ? "Settings" : "Check available tools") { model.onSettings?() }
                .font(.system(size: 11)).foregroundStyle(secondaryText).buttonStyle(.plain)
            if model.input == nil { Text("or drop a file here").font(.system(size: 10.5)).foregroundStyle(secondaryText) }
        }
        .padding(28)
        .frame(width: OrbitLayout.cardFrame.width, height: OrbitLayout.cardFrame.height)
        .modifier(OrbitGlass(shape: RoundedRectangle(cornerRadius: 32)))
        .overlay { if dropTarget { RoundedRectangle(cornerRadius: 32).strokeBorder(accent, lineWidth: 2) } }
        .position(x: OrbitLayout.cardFrame.midX, y: OrbitLayout.cardFrame.midY)
    }

    @ViewBuilder private func glassGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if #available(macOS 26.0, *) { GlassEffectContainer(spacing: 4) { content() } }
        else { content() }
    }
    private func sizeColumn(title: String, value: String) -> some View {
        VStack(spacing: 5) {
            Text(title).font(.system(size: 8, weight: .semibold)).tracking(1.2).foregroundStyle(secondaryText)
            Text(value).font(.system(size: 18, weight: .medium, design: .rounded))
        }
    }
    private func isCompression(_ action: FileAction) -> Bool { if case .compress = action.operation { return true }; return false }
    private func moveSelection(_ delta: Int) { selectedAction = OrbitLayout.nextSelection(selectedAction, delta: delta, count: actions.count) }
    private func movePreset(_ delta: Int) {
        let presets = CompressionPreset.allCases
        let current = presets.firstIndex(of: model.preset) ?? 0
        model.preset = presets[OrbitLayout.nextSelection(current, delta: delta, count: presets.count)]
    }
    private func presetSymbol(_ preset: CompressionPreset) -> String {
        switch preset { case .gentle: return "leaf"; case .balanced: return "slider.horizontal.3"; case .small: return "arrow.down.right.and.arrow.up.left" }
    }
    private func presetCaption(_ preset: CompressionPreset) -> String {
        switch preset {
        case .gentle: return FileKind.detect(model.input ?? URL(fileURLWithPath: "/")) == .pdf ? "Optimize structure · Preserve image detail" : "Higher quality · A modest reduction"
        case .balanced: return "A balance of size and image detail"
        case .small: return "Smaller file · Less image detail"
        }
    }
    private func presetDescription(_ preset: CompressionPreset) -> String {
        if model.input.map({ FileKind.detect($0) == .pdf }) == true {
            switch preset {
            case .gentle: return "Optimize PDF structure without lossy image conversion."
            case .balanced: return "Optimize structure and eligible embedded images."
            case .small: return "Stronger JPEG compression of eligible PDF images."
            }
        }
        switch preset {
        case .gentle: return "Higher image quality. A modest reduction."
        case .balanced: return "Smaller images with a practical quality balance."
        case .small: return "Lower resolution and quality for smaller files."
        }
    }
}

private struct OrbitSegment: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let symbol: String
    let angle: Double
    let span: Double
    let active: Bool
    let perform: () -> Void

    var body: some View {
        let shape = OrbitPetal(centerAngle: angle, span: span)
        let labelPoint = OrbitLayout.polar(radius: 149, degrees: angle, center: CGPoint(x: 205, y: 205))
        Button(action: perform) {
            ZStack {
                Color.clear
                VStack(spacing: 9) {
                    Image(systemName: symbol).font(.system(size: 21, weight: .light))
                    Text(title).font(.system(size: title.count > 7 ? 11 : 12, weight: .semibold)).tracking(0.3)
                }
                .foregroundStyle(colorScheme == .dark ? (active ? OrbitNight.accent : OrbitNight.text) : (active ? orbitAccent : .primary))
                .position(labelPoint)
            }
            .frame(width: 410, height: 410)
            .modifier(OrbitGlass(shape: shape, active: active))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
    }
}

private struct OrbitGlass<S: Shape>: ViewModifier {
    let shape: S
    var active = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    private var edge: LinearGradient {
        let colors: [Color]
        if colorScheme == .dark {
            colors = active
                ? [OrbitNight.accent.opacity(0.64), OrbitNight.accent.opacity(0.24), OrbitNight.accent.opacity(0.12)]
                : [.white.opacity(0.30), .white.opacity(0.09), .white.opacity(0.035)]
        } else {
            let color = active ? orbitAccent.opacity(0.50) : Color.white.opacity(0.60)
            colors = [color, color]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    @ViewBuilder func body(content: Content) -> some View {
        glass(content)
            .overlay(shape.stroke(edge, lineWidth: 0.75).allowsHitTesting(false))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.30 : 0.08),
                    radius: colorScheme == .dark ? 14 : 11, x: 0, y: colorScheme == .dark ? 6 : 4)
    }
    @ViewBuilder private func glass(_ content: Content) -> some View {
        if reduceTransparency {
            content.background {
                if colorScheme == .dark {
                    shape.fill(active ? OrbitNight.selected : OrbitNight.surface)
                } else {
                    shape.fill(Color(NSColor.windowBackgroundColor))
                        .overlay(shape.fill(active ? orbitAccent.opacity(0.14) : .clear))
                }
            }
        } else if #available(macOS 26.0, *) {
            if colorScheme == .dark {
                content.glassEffect(.regular.tint(active ? OrbitNight.selected.opacity(0.94) : OrbitNight.surface.opacity(0.88)), in: shape)
            } else {
                content.glassEffect(active ? .regular.tint(orbitAccent.opacity(0.22)) : .regular, in: shape)
            }
        } else {
            content.background {
                shape.fill(.thinMaterial)
                    .overlay(shape.fill(colorScheme == .dark
                                        ? (active ? OrbitNight.selected : OrbitNight.surface).opacity(0.88)
                                        : (active ? orbitAccent.opacity(0.12) : .clear)))
            }
        }
    }
}
