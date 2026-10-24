import SwiftUI
import AppKit
import UniformTypeIdentifiers
import FileOrbitCore

@MainActor
struct FloatingGlassShelfView: View {
    @ObservedObject var model: GlassShelfModel
    var onClose: () -> Void = {}
    @State private var isTargeted = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: "square.stack.3d.up.fill").foregroundStyle(OrbitPalette.accent(for: colorScheme))
                Text("Glass Shelf").font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
                Button { model.isPinned.toggle() } label: { Image(systemName: model.isPinned ? "pin.fill" : "pin") }
                    .help(model.isPinned ? "Unpin shelf" : "Keep shelf visible").accessibilityLabel(model.isPinned ? "Unpin shelf" : "Pin shelf")
                Button(action: onClose) { Image(systemName: "xmark") }.help("Close shelf").accessibilityLabel("Close shelf")
            }.buttonStyle(.plain)
            if model.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up").font(.system(size: 25, weight: .light)).foregroundStyle(.secondary)
                    Text("Drop files together").font(.system(size: 12, weight: .medium))
                    Text("One destination format.\nOriginals stay untouched.").font(.system(size: 10)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Add files…", action: chooseFiles).font(.system(size: 11))
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(model.items) { item in
                            ShelfFileRow(item: item, removable: !model.isRunning) { model.remove(item.id) }
                        }
                    }
                }.frame(maxHeight: .infinity)
                HStack {
                    Text("\(model.items.count) files").font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Add", action: chooseFiles).disabled(model.isRunning)
                    Button("Clear") { model.clear() }.disabled(model.isRunning)
                }.font(.system(size: 10)).buttonStyle(.plain)
            }
            controls
        }
        .padding(13)
        .frame(width: 240, height: 280)
        .foregroundStyle(OrbitPalette.primaryText(for: colorScheme))
        .modifier(LiquidGlassStyle(shape: RoundedRectangle(cornerRadius: 25), active: isTargeted))
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isTargeted, perform: acceptDrop)
    }

    private var controls: some View {
        VStack(spacing: 7) {
            if let error = model.inputError {
                Text(error).font(.system(size: 9)).foregroundStyle(.orange).lineLimit(2)
            }
            if model.isRunning {
                ProgressView(value: model.progress).tint(OrbitPalette.accent(for: colorScheme))
                HStack {
                    Text("\(model.completedCount) of \(model.totalCount) processed").font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    Button(model.isCancelling ? "Stopping…" : "Cancel") { model.cancel() }.disabled(model.isCancelling)
                }.font(.system(size: 10))
            } else {
                Picker("Action", selection: $model.mode) {
                    Text("Convert").tag(GlassShelfModel.Mode.convert)
                    Text("Compress").tag(GlassShelfModel.Mode.compress)
                }.pickerStyle(.segmented).labelsHidden().controlSize(.small)
                HStack(spacing: 7) {
                    if model.mode == .convert {
                        if model.availableFormats.isEmpty {
                            Text("No shared format").font(.system(size: 10)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Picker("Format", selection: $model.selectedFormat) {
                                ForEach(model.availableFormats, id: \.self) { Text($0.rawValue.uppercased()).tag($0) }
                            }.labelsHidden()
                        }
                    } else {
                        Picker("Quality", selection: $model.preset) {
                            Text("Gentle").tag(CompressionPreset.gentle)
                            Text("Balanced").tag(CompressionPreset.balanced)
                            Text("Smallest").tag(CompressionPreset.small)
                        }.labelsHidden()
                    }
                    Button("Run all") { model.run() }.buttonStyle(.borderedProminent).tint(OrbitPalette.accent(for: colorScheme)).disabled(!model.canRun)
                }.controlSize(.small)
                if !model.items.isEmpty && !model.canRun {
                    Text(model.mode == .convert ? "No shared output format for this selection." : "Some files don’t support compression.")
                        .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.title = "Add files to Glass Shelf"; panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false; panel.canChooseFiles = true
        panel.begin { response in if response == .OK { model.add(panel.urls) } }
    }

    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !model.isRunning else { return false }
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                else { url = item as? URL }
                if let url { Task { @MainActor in model.add([url]) } }
            }
        }
        return !providers.isEmpty
    }
}

@MainActor
private struct ShelfFileRow: View {
    let item: GlassShelfModel.Item
    let removable: Bool
    let remove: () -> Void
    @StateObject private var inspector = FileInspector()
    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let image = inspector.thumbnail ?? inspector.fallbackIcon { Image(nsImage: image).resizable().scaledToFit() }
                else { Image(systemName: "doc") }
            }.frame(width: 28, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.url.lastPathComponent).font(.system(size: 10, weight: .medium)).lineLimit(1).truncationMode(.middle)
                Text(item.state == .waiting ? inspector.sizeText : item.state.label).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(2).help(item.state.label)
            }
            Spacer(minLength: 0)
            if item.state == .running { ProgressView().controlSize(.mini) }
            else if item.state == .complete { Image(systemName: "checkmark.circle.fill").foregroundStyle(.teal).font(.system(size: 11)) }
            if removable { Button(action: remove) { Image(systemName: "minus.circle").font(.system(size: 11)).foregroundStyle(.secondary) }.buttonStyle(.plain).accessibilityLabel("Remove \(item.url.lastPathComponent)") }
        }
        .padding(.vertical, 3)
        .task(id: item.url) { inspector.load(item.url) }
        .onDisappear { inspector.cancel() }
    }
}
