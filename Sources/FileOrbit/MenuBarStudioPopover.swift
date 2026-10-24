import SwiftUI
import AppKit

@MainActor
struct MenuBarStudioPopover: View {
    @ObservedObject var preferences: StudioPreferences
    var descriptorsByMode: [String: [StudioActionDescriptor]]
    var onOpenSettings: () -> Void
    var onOpenShelf: () -> Void
    @ObservedObject private var history = JobHistory.shared
    @State private var mode = "convert"
    @State private var previewScheme: ColorScheme = .dark
    @Environment(\.colorScheme) private var colorScheme

    private var modes: [String] { ["convert", "modify", "quickActions"].filter { descriptorsByMode[$0] != nil } + descriptorsByMode.keys.sorted().filter { !["convert", "modify", "quickActions"].contains($0) } }
    private func modeTitle(_ value: String) -> String { value == "quickActions" ? "Quick Actions" : value.capitalized }
    private var descriptors: [StudioActionDescriptor] {
        let available = descriptorsByMode[mode] ?? []
        return preferences.orderedIDs(available.map(\.id), mode: mode).compactMap { id in available.first { $0.id == id } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("FileOrbit Studio").font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text("Your files. Your orbit.").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onOpenSettings) { Image(systemName: "gearshape") }.buttonStyle(.plain).help("Open settings").accessibilityLabel("Open settings")
            }
            Picker("Wheel", selection: $mode) {
                ForEach(modes, id: \.self) { Text(modeTitle($0)).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().controlSize(.small)
            HStack(alignment: .center, spacing: 12) {
                configurator
                    .environment(\.colorScheme, previewScheme)
                    .frame(width: 200, height: 200)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Make it yours").font(.system(size: 11, weight: .semibold))
                    Text("Drag an action onto another to change its place in the wheel.")
                        .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Reset order") { preferences.reset(mode: mode) }.font(.system(size: 10)).disabled(preferences.orders[mode] == nil)
                    Picker("Preview", selection: $previewScheme) {
                        Text("Light").tag(ColorScheme.light)
                        Text("Dark").tag(ColorScheme.dark)
                    }.font(.system(size: 10)).labelsHidden().help("Preview wheel appearance without changing your preference")
                }.frame(width: 93)
            }
            HStack {
                Text("Appearance").font(.system(size: 11, weight: .medium))
                Spacer()
                Picker("App appearance", selection: $preferences.appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }.labelsHidden().pickerStyle(.segmented).frame(width: 205).controlSize(.small)
            }
            Divider().opacity(0.5)
            HStack {
                Text("Recent files").font(.system(size: 11, weight: .semibold))
                Spacer()
                Button("Clear") { history.clear() }.buttonStyle(.plain).font(.system(size: 10)).disabled(history.entries.isEmpty)
            }
            if history.entries.isEmpty {
                Text("Your completed conversions appear here.").font(.system(size: 10)).foregroundStyle(.secondary).padding(.vertical, 4)
            } else {
                ForEach(Array(history.entries.prefix(3))) { entry in historyRow(entry) }
            }
            Toggle("Remember history on this Mac", isOn: $preferences.rememberHistory)
                .font(.system(size: 10)).toggleStyle(.switch).controlSize(.mini)
                .onChange(of: preferences.rememberHistory) { _, enabled in history.setRememberHistory(enabled) }
            HStack {
                Label("Everything stays local", systemImage: "lock.shield").font(.system(size: 9)).foregroundStyle(.secondary)
                Spacer()
                Button("Open Shelf", action: onOpenShelf).controlSize(.small)
            }
        }
        .padding(18)
        .frame(width: 355)
        .foregroundStyle(OrbitPalette.primaryText(for: colorScheme))
        .modifier(LiquidGlassStyle(shape: RoundedRectangle(cornerRadius: 24)))
        .onAppear { if !modes.contains(mode), let first = modes.first { mode = first } }
        .onChange(of: preferences.appearance) { _, value in
            NSApp.appearance = value == "dark" ? NSAppearance(named: .darkAqua) : value == "light" ? NSAppearance(named: .aqua) : nil
        }
    }

    private var configurator: some View {
        GeometryReader { proxy in
            let count = descriptors.count
            ZStack {
                Circle().fill(previewScheme == .dark ? Color(red: 0.07, green: 0.12, blue: 0.15) : Color(red: 0.92, green: 0.96, blue: 0.97))
                Circle().strokeBorder(.white.opacity(previewScheme == .dark ? 0.13 : 0.8), lineWidth: 1)
                VStack(spacing: 4) {
                    Image(systemName: "command").font(.system(size: 16, weight: .light))
                    Text("Drag to arrange").font(.system(size: 8))
                }.foregroundStyle(OrbitPalette.secondaryText(for: previewScheme))
                ForEach(Array(descriptors.enumerated()), id: \.element.id) { index, descriptor in
                    let angle = Double(index) * 2 * .pi / Double(max(1, count)) - .pi / 2
                    actionTile(descriptor, index: index)
                        .position(x: proxy.size.width / 2 + 72 * cos(angle), y: proxy.size.height / 2 + 72 * sin(angle))
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(modeTitle(mode)) action order")
    }

    private func actionTile(_ descriptor: StudioActionDescriptor, index: Int) -> some View {
        VStack(spacing: 3) {
            Image(systemName: descriptor.symbol).font(.system(size: 13, weight: .medium))
            Text(descriptor.title).font(.system(size: 7, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(width: 47, height: 43)
        .foregroundStyle(OrbitPalette.primaryText(for: previewScheme))
        .modifier(LiquidGlassStyle(shape: RoundedRectangle(cornerRadius: 12)))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .draggable(descriptor.id)
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first, descriptors.contains(where: { $0.id == id }) else { return false }
            preferences.move(id: id, before: descriptor.id, availableIDs: descriptors.map(\.id), mode: mode)
            return true
        }
        .contextMenu {
            Button("Move counterclockwise") { move(descriptor.id, by: -1) }
            Button("Move clockwise") { move(descriptor.id, by: 1) }
        }
        .accessibilityLabel("\(descriptor.title), position \(index + 1)")
        .accessibilityHint("Drag onto another action to reorder, or use the context menu")
        .accessibilityAction(named: Text("Move clockwise")) { move(descriptor.id, by: 1) }
        .accessibilityAction(named: Text("Move counterclockwise")) { move(descriptor.id, by: -1) }
    }

    private func move(_ id: String, by delta: Int) {
        var ids = descriptors.map(\.id)
        guard let index = ids.firstIndex(of: id), ids.count > 1 else { return }
        ids.remove(at: index)
        let target = (index + delta + ids.count + 1) % (ids.count + 1)
        ids.insert(id, at: target)
        preferences.setOrder(ids, mode: mode)
    }

    private func historyRow(_ entry: JobHistoryEntry) -> some View {
        let existing = entry.outputURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
        return Button { NSWorkspace.shared.activateFileViewerSelecting(existing) } label: {
            HStack(spacing: 8) {
                Image(systemName: "doc.badge.checkmark").foregroundStyle(OrbitPalette.accent(for: colorScheme))
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.inputName).font(.system(size: 10, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    Text("\(entry.outputPaths.count) output\(entry.outputPaths.count == 1 ? "" : "s") · \(ByteCountFormatter.string(fromByteCount: entry.outputBytes, countStyle: .file))")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.forward").font(.system(size: 9)).foregroundStyle(.secondary)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(existing.isEmpty).help(existing.isEmpty ? "Output no longer exists at its saved location" : "Reveal output in Finder")
    }
}
