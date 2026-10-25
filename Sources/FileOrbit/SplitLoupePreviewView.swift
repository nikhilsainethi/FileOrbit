import SwiftUI
import AppKit
import FileOrbitCore

@MainActor final class SplitLoupeModel: ObservableObject {
    @Published private(set) var isVisible = false
    @Published private(set) var result: ImagePreviewResult?
    @Published private(set) var message: String?
    private let engine = ImagePreviewActor()
    private var task: Task<Void, Never>?
    private var cancellation: CancellationToken?
    private var generation = UUID()
    private var activeKey: String?

    func show(input: URL, operation: FileOperation, environment: EngineEnvironment) {
        let key = input.path + String(describing: operation)
        guard !isVisible || key != activeKey else { return }
        hide(); isVisible = true; activeKey = key; message = nil; result = nil
        let id = generation, token = CancellationToken(); cancellation = token
        task = Task { [weak self, engine] in
            do {
                try await Task.sleep(for: .milliseconds(100))
                let preview = try await engine.preview(input: input, operation: operation, environment: environment, cancellation: token)
                guard let self, self.generation == id, !Task.isCancelled else { return }
                self.result = preview
            } catch {
                guard let self, self.generation == id, !Task.isCancelled else { return }
                self.message = error.localizedDescription
            }
        }
    }
    func hide() { generation = UUID(); task?.cancel(); task = nil; cancellation?.cancel(); cancellation = nil; isVisible = false; activeKey = nil; result = nil; message = nil }
}

struct SplitLoupePreviewView: View {
    @ObservedObject var model: SplitLoupeModel
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            LiquidGlassSurface(shape: Circle(), active: true)
            if let result = model.result, let original = NSImage(data: result.originalCropPNG), let output = NSImage(data: result.outputCropPNG) {
                ZStack {
                    Image(nsImage: original).resizable().interpolation(.none).frame(width: 260, height: 260)
                        .mask(alignment: .leading) { Rectangle().frame(width: 130) }
                    Image(nsImage: output).resizable().interpolation(.none).frame(width: 260, height: 260)
                        .mask(alignment: .trailing) { Rectangle().frame(width: 130) }
                    Rectangle().fill(.white.opacity(0.9)).frame(width: 1)
                    VStack {
                        HStack(spacing: 16) {
                            Text("ORIGINAL").frame(width: 70)
                            Text("OUTPUT").frame(width: 70)
                        }
                        .font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                        .padding(.vertical, 5).background(.black.opacity(0.65), in: Capsule()).padding(.top, 38)
                        Spacer()
                        Text(byteLabel(result)).font(.system(size: 9, weight: .semibold)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.8).padding(.horizontal, 8).padding(.vertical, 6)
                            .frame(maxWidth: 206).background(.ultraThickMaterial, in: Capsule()).padding(.bottom, 38)
                    }
                }.clipShape(Circle()).padding(2)
                .accessibilityLabel(result.comparisonNote + " " + byteLabel(result))
            } else {
                VStack(spacing: 10) {
                    if model.message == nil { ProgressView().controlSize(.small) }
                    Text(model.message ?? "Encoding a real preview…")
                        .font(.system(size: 12, weight: .medium)).multilineTextAlignment(.center).frame(width: 200)
                    Text("Release Space to return").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }.frame(width: 260, height: 260)
            .foregroundStyle(OrbitPalette.primaryText(for: scheme)).allowsHitTesting(false)
            .help(model.result?.comparisonNote ?? "Real local image comparison")
    }
    private func byteLabel(_ result: ImagePreviewResult) -> String {
        let a = ByteCountFormatter.string(fromByteCount: Int64(result.inputBytes), countStyle: .file)
        let b = ByteCountFormatter.string(fromByteCount: Int64(result.outputBytes), countStyle: .file)
        let delta = Int((Double(result.outputBytes) / Double(max(1, result.inputBytes)) - 1) * 100)
        return "\(a) → \(b) (\(delta > 0 ? "+" : "")\(delta)%) · SSIM \(String(format: "%.1f", result.ssim * 100))%"
    }
}

struct NeuralHubShimmer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0/30, paused: reduceMotion)) { timeline in
            let phase = reduceMotion ? 0.5 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8
            LinearGradient(colors: [.clear, .cyan.opacity(0.5), .white.opacity(0.8), .purple.opacity(0.25), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(width: 65).rotationEffect(.degrees(22)).offset(x: phase * 240 - 120)
        }.clipShape(Circle()).allowsHitTesting(false).accessibilityHidden(true)
    }
}
struct QualityPreviewStage: View {
    @StateObject private var model = SplitLoupeModel()
    @State private var assets: OnboardingSandboxAssets?
    @State private var format: OutputFormat = .jpg
    @State private var error: String?
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(spacing: 12) {
            Text("See the difference.").font(.system(size: 20, weight: .semibold, design: .rounded))
            Picker("Output", selection: $format) { Text("JPEG").tag(OutputFormat.jpg); Text("PNG").tag(OutputFormat.png); Text("HEIC").tag(OutputFormat.heic) }
                .pickerStyle(.segmented).frame(width: 250)
            SplitLoupePreviewView(model: model)
            Text(error ?? model.result?.comparisonNote ?? "Synthetic sample · actual local encoding")
                .font(.system(size: 9)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true).frame(width: 330)
        }.padding(20).frame(width: 400, height: 420).foregroundStyle(OrbitPalette.primaryText(for: scheme))
            .tint(OrbitPalette.accent(for: scheme))
            .modifier(LiquidGlassStyle(shape: RoundedRectangle(cornerRadius: 24)))
            .onAppear { do { assets = try OnboardingSandboxAssets.create(); encode() } catch { self.error = error.localizedDescription } }
            .onChange(of: format) { encode() }
            .onDisappear { model.hide(); if let assets { try? FileManager.default.removeItem(at: assets.directory) }; assets = nil }
    }
    private func encode() { if let assets { model.show(input: assets.portrait, operation: .convert(format), environment: .discover()) } }
}
#if FILEORBIT_XCODE_PREVIEWS
#Preview("Split Loupe • Light") { QualityPreviewStage().preferredColorScheme(.light) }
#Preview("Split Loupe • Dark") { QualityPreviewStage().preferredColorScheme(.dark) }
#Preview("Neural Shimmer • Light") { NeuralHubShimmer().frame(width: 104, height: 104).preferredColorScheme(.light) }
#Preview("Neural Shimmer • Dark") { NeuralHubShimmer().frame(width: 104, height: 104).preferredColorScheme(.dark) }
#endif
