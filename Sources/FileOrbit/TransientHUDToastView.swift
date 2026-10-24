import SwiftUI

@MainActor
struct TransientHUDToastView: View {
    @ObservedObject var model: JobHUDModel
    var onClose: () -> Void = {}
    @State private var hovering = false
    @State private var showingNote = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            status.frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(model.title).font(.system(size: 11, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    if let note = model.result?.note, !note.isEmpty {
                        Button { showingNote.toggle() } label: { Image(systemName: "info.circle").font(.system(size: 10)).foregroundStyle(.secondary) }
                            .buttonStyle(.plain).help(note).accessibilityLabel("Output details")
                            .popover(isPresented: $showingNote) { Text(note).font(.system(size: 12)).padding(16).frame(width: 280) }
                    }
                }
                if hovering && model.phase == .complete {
                    HStack(spacing: 14) {
                        tool("eye", title: "Quick Look (Space)", action: model.quickLook).disabled(model.onQuickLook == nil)
                        tool("doc.on.doc", title: "Copy output files", action: model.copyURLs)
                        tool("folder", title: "Reveal in Finder", action: model.reveal)
                        tool("arrow.uturn.backward", title: model.isUndoing ? "Undoing…" : "Move unchanged outputs to Trash", action: model.undo).disabled(!model.canUndo || model.isUndoing)
                    }.font(.system(size: 11)).frame(height: 13)
                } else {
                    Text(model.detail).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).help(model.detail).frame(height: 13)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if model.phase == .running {
                Button { model.cancel() } label: { Image(systemName: "xmark.circle").font(.system(size: 13)).foregroundStyle(.secondary) }
                    .buttonStyle(.plain).disabled(model.onCancel == nil || model.isCancelling).help("Cancel operation").accessibilityLabel("Cancel operation")
            } else {
                Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 9)).foregroundStyle(.secondary) }
                    .buttonStyle(.plain).accessibilityLabel("Dismiss notification")
            }
        }
        .padding(.horizontal, 13)
        .frame(width: 300, height: 54)
        .foregroundStyle(OrbitPalette.primaryText(for: colorScheme))
        .modifier(LiquidGlassStyle(shape: Capsule()))
        .onHover { value in withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) { hovering = value } }
        .focusable().focusEffectDisabled()
        .onKeyPress(.space) {
            guard model.phase == .complete, model.onQuickLook != nil else { return .ignored }
            model.quickLook(); return .handled
        }
    }

    @ViewBuilder private var status: some View {
        if model.phase == .running {
            if let progress = model.progress {
                ZStack {
                    Circle().stroke(.secondary.opacity(0.16), lineWidth: 2)
                    Circle().trim(from: 0, to: progress).stroke(OrbitPalette.accent(for: colorScheme), style: StrokeStyle(lineWidth: 2, lineCap: .round)).rotationEffect(.degrees(-90))
                    Text("\(Int(progress * 100))").font(.system(size: 8, weight: .medium, design: .rounded))
                }.accessibilityLabel("\(Int(progress * 100)) percent complete")
            } else { ProgressView().controlSize(.small).accessibilityLabel("Processing") }
        } else {
            Image(systemName: model.phase == .failed ? "exclamationmark.circle" : model.phase == .undone ? "arrow.uturn.backward.circle" : "checkmark.circle.fill")
                .font(.system(size: 25, weight: .light))
                .foregroundStyle(model.phase == .failed ? Color.orange : OrbitPalette.accent(for: colorScheme))
        }
    }
    private func tool(_ symbol: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }.buttonStyle(.plain).help(title).accessibilityLabel(title)
    }
}
