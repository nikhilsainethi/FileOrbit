import SwiftUI
import AppKit
import UniformTypeIdentifiers
import FileOrbitCore

private let orbitAccent = Color(red: 0.17, green: 0.72, blue: 0.66)

struct OrbitView: View {
    @ObservedObject var model: AppModel
    @State private var dropTarget = false
    @State private var selectedAction = 0
    @FocusState private var wheelFocused: Bool
    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch model.stage {
                case .ready: ready
                case .compression: compression
                case .working: working
                case .result: completion
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .id(model.stage)
        .frame(width: 528, height: 668)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color(NSColor.windowBackgroundColor).opacity(0.48)
                RadialGradient(colors: [orbitAccent.opacity(0.13), .clear], center: .topLeading, startRadius: 20, endRadius: 480)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(.white.opacity(0.3), lineWidth: 1))
        .overlay { if dropTarget { RoundedRectangle(cornerRadius: 30).stroke(orbitAccent, lineWidth: 3).padding(3) } }
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
        .onExitCommand { if model.stage == .compression { model.back() } else if model.stage != .working { model.onDismiss?() } }
        .onChange(of: model.input) { _, _ in selectedAction = 0; wheelFocused = true }
    }
    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().stroke(orbitAccent.opacity(0.65), lineWidth: 1.5).frame(width: 25, height: 25)
                Circle().fill(orbitAccent).frame(width: 7, height: 7).offset(x: 10, y: -8)
                Circle().fill(.primary).frame(width: 5, height: 5)
            }.frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("FileOrbit").font(.system(size: 17, weight: .semibold, design: .rounded))
                Text("A little space for your files.").font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { model.onSettings?() } label: { Image(systemName: "gearshape").font(.system(size: 16)) }.buttonStyle(.plain).help("Settings").accessibilityLabel("Settings")
            Button { model.onDismiss?() } label: { Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).frame(width: 26, height: 26).background(.primary.opacity(0.06), in: Circle()) }.buttonStyle(.plain).help("Close").accessibilityLabel("Close FileOrbit")
        }.padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 20)
    }
    @ViewBuilder private var ready: some View {
        if let input = model.input {
            VStack(spacing: 6) {
                Text(input.lastPathComponent).font(.system(size: 18, weight: .semibold)).lineLimit(1).truncationMode(.middle).padding(.horizontal, 40)
                Text("CHOOSE WHAT’S NEXT").font(.system(size: 9, weight: .medium)).tracking(2.4).foregroundStyle(.secondary).padding(.top, 2)
                if model.actions.isEmpty {
                    VStack(spacing: 16) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: input.path)).resizable().frame(width: 64, height: 64)
                        Text("No available actions").font(.title3.weight(.medium))
                        Text(model.dependencyHint ?? "This file type is not supported yet. Choose an image, PDF, Office document, text file, or SVG.")
                            .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 350)
                        Button("Open Settings") { model.onSettings?() }.buttonStyle(.bordered)
                    }.frame(height: 340)
                } else {
                    wheel(input: input).frame(width: 430, height: 418)
                        .focusable().focusEffectDisabled().focused($wheelFocused)
                        .onAppear { wheelFocused = true }
                        .onKeyPress(.rightArrow) { selectedAction = (selectedAction + 1) % model.actions.count; return .handled }
                        .onKeyPress(.leftArrow) { selectedAction = (selectedAction + model.actions.count - 1) % model.actions.count; return .handled }
                        .onKeyPress(.downArrow) { selectedAction = (selectedAction + 1) % model.actions.count; return .handled }
                        .onKeyPress(.upArrow) { selectedAction = (selectedAction + model.actions.count - 1) % model.actions.count; return .handled }
                        .onKeyPress(.return) { if model.actions.indices.contains(selectedAction) { model.perform(model.actions[selectedAction]) }; return .handled }
                    if let hint = model.dependencyHint { Text(hint).font(.system(size: 10)).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 30).lineLimit(2) }
                }
                Spacer(minLength: 0)
            }
        } else {
            VStack(spacing: 20) {
                ZStack {
                    ForEach(0..<3) { index in Circle().stroke(orbitAccent.opacity(0.18 - Double(index) * 0.04), lineWidth: 1).frame(width: CGFloat(110 + index * 50), height: CGFloat(110 + index * 50)) }
                    Image(systemName: "doc.on.doc").font(.system(size: 43, weight: .ultraLight)).foregroundStyle(orbitAccent)
                    Circle().fill(orbitAccent).frame(width: 11, height: 11).offset(x: 84, y: -62)
                }.frame(height: 210)
                VStack(spacing: 9) {
                    Text("Your files. A new possibility.").font(.system(size: 24, weight: .medium, design: .rounded))
                    Text("Select a file in Finder. Tap ⌘ twice.\nConvert or compress, right where you are.")
                        .font(.system(size: 14)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
                }
                Button { model.chooseFile() } label: { Label("Choose a file", systemImage: "plus").frame(width: 170).padding(.vertical, 8) }.buttonStyle(.borderedProminent).tint(orbitAccent)
                Text("or drop a file anywhere in this window").font(.system(size: 11)).foregroundStyle(.secondary)
                if !model.accessibilityGranted {
                    Button("Set up double-tap Command →") { model.onSettings?() }.font(.system(size: 12)).buttonStyle(.plain).foregroundStyle(orbitAccent)
                }
                Spacer(minLength: 4)
            }.padding(.horizontal, 26)
        }
    }
    private func wheel(input: URL) -> some View {
        ZStack {
            Circle().stroke(.primary.opacity(0.035), lineWidth: 1).frame(width: 414, height: 414)
            ForEach(Array(model.actions.enumerated()), id: \.element.id) { index, action in
                OrbitSegment(action: action, index: index, count: model.actions.count, keyboardSelected: wheelFocused && index == selectedAction) { model.perform(action) }
            }
            VStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: input.path)).resizable().interpolation(.high).frame(width: 46, height: 46)
                Text(input.pathExtension.uppercased()).font(.system(size: 12, weight: .semibold)).tracking(1.5)
                Text(model.inputSize).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(width: 156, height: 156)
            .background(.regularMaterial, in: Circle())
            .modifier(OrbitGlass(shape: Circle()))
            .overlay(Circle().strokeBorder(.white.opacity(0.30), lineWidth: 1))
            .shadow(color: .black.opacity(0.06), radius: 15, y: 5)
            .accessibilityElement(children: .combine)
        }
    }
    private var compression: some View {
        VStack(alignment: .leading, spacing: 20) {
            Button { model.back() } label: { Label("All actions", systemImage: "arrow.left") }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                Text("A lighter file.").font(.system(size: 29, weight: .medium, design: .rounded))
                Text("Choose a balance of size and detail.").font(.system(size: 14)).foregroundStyle(.secondary)
            }
            ForEach(CompressionPreset.allCases, id: \.self) { preset in
                Button { model.preset = preset } label: {
                    HStack(spacing: 14) {
                        Image(systemName: preset == .gentle ? "leaf" : preset == .balanced ? "slider.horizontal.3" : "arrow.down.right.and.arrow.up.left").font(.system(size: 20)).frame(width: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(preset.rawValue.capitalized).font(.system(size: 15, weight: .semibold))
                            Text(presetDescription(preset)).font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                        }
                        Spacer()
                        Image(systemName: model.preset == preset ? "checkmark.circle.fill" : "circle").foregroundStyle(model.preset == preset ? orbitAccent : .secondary)
                    }.padding(16).frame(maxWidth: .infinity).background(model.preset == preset ? orbitAccent.opacity(0.11) : .primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 15))
                        .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(model.preset == preset ? orbitAccent.opacity(0.7) : .clear, lineWidth: 1))
                }.buttonStyle(.plain)
            }
            Text("A separate copy is saved only if it is smaller. Stronger settings can reduce image detail. Your original stays intact.")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
            Button { model.run(.compress(model.preset)) } label: { Label("Compress file", systemImage: "arrow.down.right.and.arrow.up.left").frame(maxWidth: .infinity).padding(.vertical, 9) }.buttonStyle(.borderedProminent).tint(orbitAccent)
            Spacer(minLength: 0)
        }.padding(.horizontal, 36)
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
    private var working: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle().stroke(orbitAccent.opacity(0.14), lineWidth: 1).frame(width: 160, height: 160)
                ProgressView().controlSize(.large)
            }
            Text(model.cancelling ? "Cancelling…" : "Making the next version.").font(.system(size: 24, weight: .medium, design: .rounded))
            Text("Processing on your Mac. Your original is safe.").font(.system(size: 13)).foregroundStyle(.secondary)
            Text(model.input?.lastPathComponent ?? "").font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).frame(maxWidth: 360)
            Button("Cancel") { model.cancel() }.buttonStyle(.bordered).disabled(model.cancelling)
        }.frame(maxHeight: .infinity)
    }
    private var completion: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark").font(.system(size: 30, weight: .light)).foregroundStyle(orbitAccent).frame(width: 86, height: 86).background(orbitAccent.opacity(0.12), in: Circle())
            Text("Ready for what’s next.").font(.system(size: 25, weight: .medium, design: .rounded))
            if let result = model.result {
                Text(result.outputURLs.count == 1 ? (result.outputURLs.first?.lastPathComponent ?? "File saved") : "\(result.outputURLs.count) files saved")
                    .font(.system(size: 14, weight: .medium)).lineLimit(2).multilineTextAlignment(.center).padding(.horizontal, 30)
                HStack(spacing: 18) {
                    VStack(spacing: 5) { Text("ORIGINAL").font(.system(size: 9)).tracking(1.5); Text(AppModel.bytes(result.inputBytes)).font(.system(size: 19, weight: .medium)) }
                    Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                    VStack(spacing: 5) { Text("RESULT").font(.system(size: 9)).tracking(1.5); Text(AppModel.bytes(result.outputBytes)).font(.system(size: 19, weight: .medium)).foregroundStyle(orbitAccent) }
                }.padding(22).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
                if let note = result.note { Text(note).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 35) }
                Button { model.reveal() } label: { Label("Show in Finder", systemImage: "folder").frame(width: 190).padding(.vertical, 8) }.buttonStyle(.borderedProminent).tint(orbitAccent)
                Button("Back to original file") { model.back() }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
    private func errorBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle").padding(.top, 1)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }.font(.system(size: 11)).foregroundStyle(.primary.opacity(0.8)).padding(12)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 26)
    }
    private var footer: some View {
        VStack(spacing: 13) {
            Rectangle().fill(.primary.opacity(0.07)).frame(height: 1)
            HStack {
                Label("On your Mac", systemImage: "lock.shield").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                if model.input != nil {
                    Button("Choose another file") { model.chooseFile() }.buttonStyle(.plain).font(.system(size: 11)).disabled(model.stage == .working)
                } else { Text("⌘  ⌘").font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundStyle(.secondary) }
            }
        }.padding(.horizontal, 28).padding(.bottom, 23).padding(.top, 10)
    }
}

private struct OrbitSegment: View {
    let action: FileAction
    let index: Int
    let count: Int
    let keyboardSelected: Bool
    let perform: () -> Void
    @State private var hovering = false
    var isActive: Bool { hovering || keyboardSelected }
    var angle: Double { -90 + Double(index) * 360 / Double(max(count, 1)) }
    var body: some View {
        let shape = OrbitWedge(centerAngle: angle, span: 360 / Double(max(count, 1)) - 4, innerRadius: 92, outerRadius: 197)
        Button(action: perform) {
            ZStack {
                shape.fill(isActive ? orbitAccent.opacity(0.18) : Color.primary.opacity(0.035))
                    .modifier(OrbitGlass(shape: shape))
                    .overlay(shape.strokeBorderEquivalent(isActive ? orbitAccent.opacity(0.6) : Color.white.opacity(0.35)))
                VStack(spacing: 7) {
                    Image(systemName: action.symbol).font(.system(size: 19, weight: .light))
                    Text(action.title).font(.system(size: 12, weight: .semibold)).tracking(0.5)
                }
                .foregroundStyle(isActive ? orbitAccent : .primary)
                .position(x: 215 + cos(angle * .pi / 180) * 145, y: 209 + sin(angle * .pi / 180) * 145)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .help(action.subtitle)
        .accessibilityLabel(action.title + ". " + action.subtitle)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isActive)
    }
}

private struct OrbitWedge: Shape {
    let centerAngle: Double
    let span: Double
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let start = Angle.degrees(centerAngle - span / 2)
        let end = Angle.degrees(centerAngle + span / 2)
        var path = Path()
        path.addArc(center: center, radius: outerRadius, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: center, radius: innerRadius, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }
    func strokeBorderEquivalent(_ color: Color) -> some View { self.stroke(color, lineWidth: 1) }
}

private struct OrbitGlass<S: Shape>: ViewModifier {
    let shape: S
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) { content.glassEffect(.regular, in: shape) }
        else { content.background(.thinMaterial, in: shape) }
    }
}
