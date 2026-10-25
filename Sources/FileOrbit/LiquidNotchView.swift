import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
struct LiquidNotchView: View {
    @ObservedObject var model: NotchPortalModel
    @ObservedObject var stash: NotchStashModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stashTargeted = false
    @State private var pipelineTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            if model.expanded { receptionBay }
            else {
                Button { model.expanded = true; model.showsShelf = !stash.items.isEmpty } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "circle.hexagongrid.fill").font(.system(size: 11))
                        Text(stash.items.isEmpty ? "FileOrbit" : "\(stash.items.count) pinned").font(.system(size: 10, weight: .semibold))
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }.buttonStyle(.plain).accessibilityLabel("Expand FileOrbit Notch Shelf")
            }
            if model.expanded && model.showsShelf { shelf }
        }
        .frame(width: model.width, height: model.height)
        .foregroundStyle(OrbitPalette.primaryText(for: scheme))
        .tint(OrbitPalette.accent(for: scheme))
        .background {
            LiquidGlassSurface(shape: UnevenRoundedRectangle(topLeadingRadius: model.hasHardwareNotch ? 5 : 14,
                                                             bottomLeadingRadius: model.expanded ? 24 : 14,
                                                             bottomTrailingRadius: model.expanded ? 24 : 14,
                                                             topTrailingRadius: model.hasHardwareNotch ? 5 : 14),
                               active: model.isDragging || stashTargeted || pipelineTargeted)
        }
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.76), value: model.expanded)
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.76), value: model.showsShelf)
        .onHover { model.hovered = $0 }
    }

    private var receptionBay: some View {
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                dropZone(title: "Quick Stash", subtitle: "Keep a reference", symbol: "tray.and.arrow.down", active: stashTargeted) {
                    model.toggleShelf()
                }
                .onDrop(of: [UTType.fileURL.identifier], isTargeted: $stashTargeted) { providers in
                    receive(providers, action: model.onStash)
                }
                Rectangle().fill(OrbitPalette.secondaryText(for: scheme).opacity(0.16)).frame(width: 1, height: 35)
                dropZone(title: "Instant Pipeline", subtitle: model.pipelineTitle, symbol: model.processing ? "ellipsis" : "bolt.fill", active: pipelineTargeted) { model.status = "Drop compatible files here to run your pinned pipeline." }
                    .onDrop(of: [UTType.fileURL.identifier], isTargeted: $pipelineTargeted) { providers in
                        guard !model.processing else { return false }
                        return receive(providers, action: model.onPipeline)
                    }
            }.padding(.horizontal, 12).padding(.top, 9)
            HStack(spacing: 6) {
                Text(model.status ?? "Drop left to pin · right to run locally")
                    .font(.system(size: 9)).foregroundStyle(OrbitPalette.secondaryText(for: scheme))
                    .lineLimit(1).truncationMode(.middle).help(model.status ?? "")
                Spacer(minLength: 0)
                if model.processing { Button("Cancel") { model.onCancelPipeline?() }.font(.system(size: 9)) }
                Button { model.onClose?() } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .semibold)) }
                    .buttonStyle(.plain).accessibilityLabel("Hide Notch Portal")
            }.padding(.horizontal, 15).padding(.bottom, 9)
        }.frame(height: 96)
    }

    private func dropZone(title: String, subtitle: String, symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 20, weight: .light)).frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 11, weight: .semibold))
                    Text(subtitle).font(.system(size: 8)).foregroundStyle(OrbitPalette.secondaryText(for: scheme)).lineLimit(2)
                }
                Spacer(minLength: 0)
            }.padding(9).frame(maxWidth: .infinity, minHeight: 56, maxHeight: 56)
                .background(OrbitPalette.accent(for: scheme).opacity(active ? 0.18 : 0.03), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(OrbitPalette.accent(for: scheme).opacity(active ? 0.7 : 0.1), lineWidth: 0.8))
        }.buttonStyle(.plain).accessibilityLabel(title + ". " + subtitle)
    }

    private var shelf: some View {
        VStack(spacing: 7) {
            Divider().opacity(0.5)
            HStack {
                Text("PINNED REFERENCES").font(.system(size: 9, weight: .semibold)).tracking(1)
                Spacer()
                Button("Clear") { stash.clear() }.disabled(stash.items.isEmpty)
                Button { model.showsShelf = false } label: { Image(systemName: "chevron.up") }.accessibilityLabel("Collapse pinned files")
            }.font(.system(size: 9)).buttonStyle(.plain)
            if stash.items.isEmpty {
                ContentUnavailableView { Label("Ready for your files", systemImage: "tray") }
                    description: { Text("Drop files into Quick Stash. Their originals stay in place.").font(.caption) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(stash.items) { item in
                            HStack(spacing: 7) {
                                Image(systemName: item.isAvailable ? "doc" : "exclamationmark.triangle").font(.system(size: 13))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(.system(size: 10, weight: .medium)).lineLimit(1).truncationMode(.middle)
                                    if !item.isAvailable { Text("File unavailable").font(.system(size: 9)).foregroundStyle(.orange) }
                                }
                                Spacer(minLength: 0)
                                Button { stash.reveal(item.id) } label: { Image(systemName: "arrow.up.forward.square").font(.system(size: 10)) }
                                    .disabled(!item.isAvailable).accessibilityLabel("Reveal \(item.title)")
                                Button { stash.remove(item.id) } label: { Image(systemName: "minus.circle").font(.system(size: 10)) }
                                    .accessibilityLabel("Remove reference to \(item.title)")
                            }.buttonStyle(.plain).padding(.vertical, 4)
                        }
                    }
                }
            }
        }.padding(.horizontal, 15).padding(.bottom, 12).frame(height: 170)
    }

    private func receive(_ providers: [NSItemProvider], action: (([URL]) -> Void)?) -> Bool {
        guard !providers.isEmpty, let action else { return false }
        Task { @MainActor in
            let urls = await OrbitDropSession.load(Array(providers.prefix(NotchStashModel.maximumItems)))
            guard !urls.isEmpty else { return }
            action(urls)
        }
        return true
    }
}

#if FILEORBIT_XCODE_PREVIEWS
#Preview("Liquid Notch · Quartz") { NotchPreviewStage().preferredColorScheme(.light) }
#Preview("Liquid Notch · Obsidian") { NotchPreviewStage().preferredColorScheme(.dark) }
@MainActor private struct NotchPreviewStage: View {
    @StateObject private var model = NotchPortalModel()
    @StateObject private var stash = NotchStashModel(defaults: UserDefaults(suiteName: "FileOrbit.NotchCanvas")!)
    var body: some View {
        LiquidNotchView(model: model, stash: stash).padding(32).frame(width: 420, height: 330)
            .onAppear { model.expanded = true; model.showsShelf = true }
    }
}
#endif
