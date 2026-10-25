import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ImpactBentoView: View {
    @ObservedObject var store: ImpactStore
    @Environment(\.colorScheme) private var scheme
    @State private var message: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Your local impact").font(.system(size: 12, weight: .semibold))
                Spacer()
                Button("Reset") { store.clear() }.font(.system(size: 9)).buttonStyle(.plain).disabled(store.totalOperations == 0)
            }
            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 8) {
                card {
                    Text(ByteCountFormatter.string(fromByteCount: store.avoidedBytes, countStyle: .file)).font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
                    Text("Smaller outputs").font(.system(size: 10, weight: .medium))
                    ImpactSparkline(values: store.sparkline).stroke(OrbitPalette.accent(for: scheme), style: StrokeStyle(lineWidth: 2, lineCap: .round)).frame(height: 22)
                }
                card {
                    HStack {
                        ImpactRing(store: store).frame(width: 38, height: 38)
                        Text("\(store.totalOperations)").font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                    }
                    Text("Files transformed").font(.system(size: 10, weight: .medium))
                    Text("Convert · Compress · Neural").font(.system(size: 7)).foregroundStyle(.secondary)
                }
                card {
                    Text(timeLabel).font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text("Estimated time saved").font(.system(size: 10, weight: .medium))
                    Text("20 seconds per completed file").font(.system(size: 7)).foregroundStyle(.secondary)
                }
                card {
                    Image(systemName: "sparkles.rectangle.stack").font(.system(size: 20)).foregroundStyle(OrbitPalette.accent(for: scheme))
                    Text("Share your impact").font(.system(size: 10, weight: .medium))
                    HStack(spacing: 8) {
                        Button("Copy") { export(toDesktop: false) }
                        Button("Desktop") { export(toDesktop: true) }
                    }.font(.system(size: 9)).buttonStyle(.plain)
                }
            }
            Text(message ?? "Originals stay intact. Smaller outputs measures byte reduction, not disk space freed.")
                .font(.system(size: 8)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var timeLabel: String { store.estimatedSeconds < 60 ? "\(store.estimatedSeconds)s" : String(format: "%.1f min", Double(store.estimatedSeconds) / 60) }
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6, content: content).frame(maxWidth: .infinity, minHeight: 82, alignment: .leading).padding(11)
            .background(OrbitPalette.accent(for: scheme).opacity(scheme == .dark ? 0.07 : 0.045), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.primary.opacity(0.08), lineWidth: 0.5))
    }
    @MainActor private func export(toDesktop: Bool) {
        let renderer = ImageRenderer(content: ImpactShareCard(bytes: store.avoidedBytes, operations: store.totalOperations, seconds: store.estimatedSeconds, dark: scheme == .dark))
        renderer.scale = 3
        guard let cgImage = renderer.cgImage, let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else { message = "Could not render the impact card."; return }
        do {
            if toDesktop {
                let folder = try FileManager.default.url(for: .desktopDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
                let url = folder.appendingPathComponent("FileOrbit Impact \(UUID().uuidString.prefix(8)).png")
                try png.write(to: url, options: .withoutOverwriting); NSWorkspace.shared.activateFileViewerSelecting([url]); message = "Impact card saved to Desktop at 3×."
            } else {
                message = FileOrbitClipboard.write(png, type: .png) == .written ? "Impact card copied at 3×." : "Could not copy the impact card."
            }
        } catch { message = error.localizedDescription }
    }
}
private struct ImpactSparkline: Shape {
    let values: [Double]
    func path(in rect: CGRect) -> Path {
        var path = Path(); guard values.count > 1 else { return path }
        let maximum = max(1, values.max() ?? 1)
        for (index, value) in values.enumerated() {
            let point = CGPoint(x: rect.minX + CGFloat(index) / CGFloat(values.count - 1) * rect.width, y: rect.maxY - CGFloat(value / maximum) * rect.height)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}
private struct ImpactRing: View {
    @ObservedObject var store: ImpactStore
    let colors: [Color] = [.teal, .cyan, .indigo, .purple]
    var body: some View {
        ZStack {
            Circle().stroke(.secondary.opacity(0.15), lineWidth: 6)
            ForEach(Array(ImpactCategory.allCases.enumerated()), id: \.element) { index, category in
                let earlier = ImpactCategory.allCases.prefix(index).reduce(Int64(0)) { $0 + store.state.operations[$1.rawValue, default: 0] }
                let count = store.state.operations[category.rawValue, default: 0]
                Circle().trim(from: CGFloat(earlier) / CGFloat(max(1, store.totalOperations)), to: CGFloat(earlier + count) / CGFloat(max(1, store.totalOperations)))
                    .stroke(colors[index], style: StrokeStyle(lineWidth: 6, lineCap: .butt)).rotationEffect(.degrees(-90))
            }
        }.accessibilityLabel(ImpactCategory.allCases.map { "\($0.title) \(store.state.operations[$0.rawValue, default: 0])" }.joined(separator: ", "))
    }
}
struct ImpactShareCard: View {
    let bytes: Int64
    let operations: Int64
    let seconds: Int64
    let dark: Bool
    var body: some View {
        ZStack {
            LinearGradient(colors: dark ? [Color(red: 0.07, green: 0.08, blue: 0.11), Color(red: 0.08, green: 0.22, blue: 0.24)] : [Color(white: 0.99), Color(red: 0.84, green: 0.96, blue: 0.94)], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 18) {
                Label("FILEORBIT", systemImage: "circle.hexagongrid").font(.system(size: 14, weight: .bold, design: .rounded)).tracking(3)
                Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)).font(.system(size: 56, weight: .semibold, design: .rounded)).monospacedDigit()
                Text("Less weight. More possibility.").font(.system(size: 20, weight: .medium))
                HStack { Text("\(operations) files transformed"); Spacer(); Text("~\(seconds / 60) min saved*") }.font(.system(size: 13))
                Text("Output size reduction; originals preserved. *20 sec/file estimate. Processed locally.").font(.system(size: 9)).opacity(0.7)
            }.padding(34)
        }.frame(width: 540, height: 300).foregroundStyle(dark ? Color.white : Color(red: 10.0/255, green: 92.0/255, blue: 96.0/255))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.32), lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: 28))
    }
}
enum ClipboardWriteOutcome: Equatable { case written, changed, failed, cancelled
    var copyNote: String? {
        switch self { case .written: return nil; case .changed: return "Newer clipboard kept"; case .failed: return "Clipboard copy failed"; case .cancelled: return "Clipboard copy cancelled" }
    }
}
@MainActor enum FileOrbitClipboard {
    static let marker = NSPasteboard.PasteboardType("io.fileorbit.generated")
    @discardableResult static func write(_ data: Data, type: NSPasteboard.PasteboardType, text: String? = nil, expectedRevision: Int? = nil, pasteboard: NSPasteboard = .general) -> ClipboardWriteOutcome {
        if let expectedRevision, pasteboard.changeCount != expectedRevision { return .changed }
        let item = NSPasteboardItem(); item.setData(data, forType: type); item.setString("FileOrbit", forType: marker)
        if let text { item.setString(text, forType: .string) }
        pasteboard.clearContents(); return pasteboard.writeObjects([item]) ? .written : .failed
    }
}
#if FILEORBIT_XCODE_PREVIEWS
#Preview("Impact Bento • Light") { ImpactBentoView(store: ImpactStore(defaults: UserDefaults(suiteName: "FileOrbit.impact.preview")!)).padding().frame(width: 355).preferredColorScheme(.light) }
#Preview("Impact Bento • Dark") { ImpactBentoView(store: ImpactStore(defaults: UserDefaults(suiteName: "FileOrbit.impact.preview")!)).padding().frame(width: 355).preferredColorScheme(.dark) }
#Preview("Impact Card • Light") { ImpactShareCard(bytes: 0, operations: 0, seconds: 0, dark: false).preferredColorScheme(.light) }
#Preview("Impact Card • Dark") { ImpactShareCard(bytes: 0, operations: 0, seconds: 0, dark: true).preferredColorScheme(.dark) }
#endif
