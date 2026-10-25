import AppKit
import SwiftUI
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers
import ServiceManagement
import FileOrbitCore

struct OnboardingSandboxAssets: Sendable {
    let directory: URL
    let portrait: URL
    let deck: URL
    let outputDirectory: URL

    static func create() throws -> OnboardingSandboxAssets {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("FileOrbit-Onboarding-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            let portrait = folder.appendingPathComponent("Studio_Portrait.png"), deck = folder.appendingPathComponent("Sample_Deck.pdf")
            let outputs = folder.appendingPathComponent("Practice Outputs", isDirectory: true)
            try FileManager.default.createDirectory(at: outputs, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            try createPortrait(portrait); try createDeck(deck)
            return Self(directory: folder, portrait: portrait, deck: deck, outputDirectory: outputs)
        } catch { try? FileManager.default.removeItem(at: folder); throw error }
    }
    private static func createPortrait(_ url: URL) throws {
        guard let c = CGContext(data: nil, width: 640, height: 640, bitsPerComponent: 8, bytesPerRow: 2560,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ConversionError.failed("Could not create the practice portrait.") }
        let colors = [CGColor(red: 0.84, green: 0.93, blue: 0.92, alpha: 1), CGColor(red: 0.40, green: 0.64, blue: 0.67, alpha: 1)] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1]) {
            c.drawLinearGradient(gradient, start: CGPoint(x: 80, y: 640), end: CGPoint(x: 640, y: 0), options: [])
        }
        // A synthetic illustration, not a photograph of a real person.
        c.setFillColor(CGColor(red: 0.08, green: 0.20, blue: 0.28, alpha: 1))
        c.fillEllipse(in: CGRect(x: 110, y: -100, width: 420, height: 420))
        c.setFillColor(CGColor(red: 0.73, green: 0.43, blue: 0.29, alpha: 1)); c.fill(CGRect(x: 275, y: 220, width: 90, height: 130))
        c.setFillColor(CGColor(red: 0.88, green: 0.61, blue: 0.43, alpha: 1)); c.fillEllipse(in: CGRect(x: 205, y: 270, width: 230, height: 270))
        c.setFillColor(CGColor(red: 0.11, green: 0.09, blue: 0.10, alpha: 1))
        c.fillEllipse(in: CGRect(x: 198, y: 420, width: 244, height: 150))
        c.fillEllipse(in: CGRect(x: 200, y: 353, width: 50, height: 170))
        c.setFillColor(CGColor(red: 0.13, green: 0.10, blue: 0.10, alpha: 1))
        c.fillEllipse(in: CGRect(x: 263, y: 388, width: 14, height: 17)); c.fillEllipse(in: CGRect(x: 359, y: 388, width: 14, height: 17))
        c.setStrokeColor(CGColor(red: 0.53, green: 0.27, blue: 0.23, alpha: 1)); c.setLineWidth(5)
        c.move(to: CGPoint(x: 294, y: 335)); c.addQuadCurve(to: CGPoint(x: 346, y: 335), control: CGPoint(x: 320, y: 319)); c.strokePath()
        guard let image = c.makeImage(), let encoder = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw ConversionError.failed("Could not encode the practice portrait.") }
        CGImageDestinationAddImage(encoder, image, nil)
        guard CGImageDestinationFinalize(encoder) else { throw ConversionError.failed("Could not save the practice portrait.") }
    }
    private static func createDeck(_ url: URL) throws {
        var box = CGRect(x: 0, y: 0, width: 640, height: 400)
        guard let c = CGContext(url as CFURL, mediaBox: &box, nil) else { throw ConversionError.failed("Could not create the practice deck.") }
        c.beginPDFPage(nil); c.setFillColor(CGColor(red: 0.06, green: 0.12, blue: 0.16, alpha: 1)); c.fill(box)
        c.setFillColor(CGColor(red: 0.10, green: 0.72, blue: 0.64, alpha: 1)); c.fillEllipse(in: CGRect(x: 450, y: 160, width: 270, height: 270))
        let lines: [(String, CGFloat, CGFloat)] = [("FileOrbit", 46, 267), ("Local by design.", 27, 214), ("A safe sample for your first conversion.", 17, 152), ("Try PNG, JPG or Compress in the wheel.", 15, 105)]
        for (text, size, y) in lines {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, size, nil),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)
            ]))
            c.textPosition = CGPoint(x: 50, y: y); CTLineDraw(line, c)
        }
        c.endPDFPage(); c.closePDF()
    }
}

@MainActor final class OnboardingSandboxWindow: NSWindowController {
    private let assets: OnboardingSandboxAssets?
    init(onSample: @escaping @MainActor (URL, URL, Bool) -> Void,
         onNotchDemo: @escaping @MainActor () -> Void,
         onSettings: @escaping @MainActor () -> Void) {
        let assets = try? OnboardingSandboxAssets.create(); self.assets = assets
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 680, height: 460), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Welcome to FileOrbit"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.isOpaque = false; window.backgroundColor = .clear; window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentView = NSHostingView(rootView: OnboardingSandboxView(assets: assets, onSample: onSample, onNotchDemo: onNotchDemo, onSettings: onSettings, onFinish: { [weak self] in
            UserDefaults.standard.set(true, forKey: "FileOrbit.completedOnboarding"); self?.close()
        }))
        window.center()
    }
    required init?(coder: NSCoder) { return nil }
    func show() { window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
}

struct OnboardingSandboxView: View {
    let assets: OnboardingSandboxAssets?
    var onSample: @MainActor (URL, URL, Bool) -> Void
    var onNotchDemo: @MainActor () -> Void
    var onSettings: @MainActor () -> Void
    var onFinish: @MainActor () -> Void
    @ObservedObject private var modifiers = ModifierPreferences.shared
    @Environment(\.colorScheme) private var scheme
    @State private var step = 0
    @State private var selectedSample = 0
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "circle.hexagongrid.fill").font(.system(size: 24)).foregroundStyle(OrbitPalette.accent(for: scheme))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Welcome to FileOrbit").font(.system(size: 21, weight: .semibold, design: .rounded))
                    Text("A little practice. Everything stays on your Mac.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(step + 1) / 3").font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
            }.padding(.leading, 70).padding(.trailing, 28).padding(.top, 28).padding(.bottom, 18)
            Divider().opacity(0.5)
            Group {
                if step == 0 { wheelPractice }
                else if step == 1 { notchPractice }
                else { permissions }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.horizontal, 28).padding(.vertical, 18)
            Divider().opacity(0.5)
            HStack {
                Button("Back") { step = max(0, step - 1) }.disabled(step == 0)
                HStack(spacing: 6) { ForEach(0..<3) { value in Circle().fill(value == step ? OrbitPalette.accent(for: scheme) : Color.secondary.opacity(0.25)).frame(width: 5, height: 5) } }
                Spacer()
                if let error { Text(error).font(.system(size: 10)).foregroundStyle(.red).lineLimit(2) }
                Button(step == 2 ? "Start using FileOrbit" : "Continue") { if step == 2 { onFinish() } else { step += 1 } }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }.padding(.horizontal, 28).padding(.vertical, 16)
        }
        .foregroundStyle(OrbitPalette.primaryText(for: scheme)).tint(OrbitPalette.accent(for: scheme))
        .modifier(LiquidGlassStyle(shape: RoundedRectangle(cornerRadius: 20)))
        .frame(width: 680, height: 460)
    }
    private var wheelPractice: some View {
        HStack(spacing: 26) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Meet your spatial wheel").font(.system(size: 19, weight: .semibold, design: .rounded))
                Text("Drag a sample to open the real wheel. Drop it on a format to make a copy.").font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    sampleCard("Portrait", symbol: "person.crop.rectangle", index: 0)
                    sampleCard("Deck", symbol: "doc.richtext", index: 1)
                }
                Text("Synthetic samples · copies stay in a practice folder").font(.system(size: 9)).foregroundStyle(.secondary)
            }.frame(width: 306)
            VStack(alignment: .leading, spacing: 14) {
                Label("No uploads or accounts", systemImage: "lock.shield").font(.system(size: 12, weight: .medium))
                Label("Your originals stay intact", systemImage: "doc.on.doc").font(.system(size: 12, weight: .medium))
                Text("For your own files, select one in Finder and double-tap ⌘.").font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Open practice wheel") { openSample(dragging: false) }.buttonStyle(.borderedProminent).disabled(assets == nil)
                Button("Reveal practice copies") { if let assets { NSWorkspace.shared.open(assets.outputDirectory) } }.font(.system(size: 11)).disabled(assets == nil)
                if assets == nil { Text("Practice samples could not be created. Close and reopen onboarding to retry.").font(.caption).foregroundStyle(.red) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func sampleCard(_ title: String, symbol: String, index: Int) -> some View {
        let url = index == 0 ? assets?.portrait : assets?.deck
        return Button { selectedSample = index } label: {
            VStack(spacing: 7) {
                if let url, let image = NSImage(contentsOf: url) {
                    Image(nsImage: image).resizable().scaledToFill().frame(width: 120, height: 80).clipShape(RoundedRectangle(cornerRadius: 8))
                } else { Image(systemName: symbol).font(.system(size: 26)).frame(width: 120, height: 80) }
                Text(title).font(.system(size: 11, weight: .medium))
            }.padding(9).modifier(LiquidGlassStyle(shape: RoundedRectangle(cornerRadius: 13), active: selectedSample == index))
        }.buttonStyle(.plain).disabled(assets == nil)
            .onDrag {
                guard let url, let assets else { return NSItemProvider() }
                selectedSample = index; onSample(url, assets.outputDirectory, true)
                return NSItemProvider(object: url as NSURL)
            }
            .accessibilityLabel("\(title) practice sample. Drag to open the wheel.")
    }
    private var notchPractice: some View {
        HStack(spacing: 28) {
            VStack(alignment: .leading, spacing: 14) {
                Text("More room when you need it").font(.system(size: 19, weight: .semibold, design: .rounded))
                Text("Hover Compress in the wheel to open its three quality presets. A short pause unfolds the outer ring.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Practice sub-rings") { selectedSample = 0; openSample(dragging: false) }.buttonStyle(.borderedProminent).disabled(assets == nil)
                Text("During a Finder drag, hold \(modifiers.key(for: .convert)) for Convert, \(modifiers.key(for: .modify)) for Modify, or \(modifiers.key(for: .quickActions)) for Quick Actions.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(width: 305)
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 23))
                    VStack(alignment: .leading) { Text("Quick Stash").font(.system(size: 12, weight: .semibold)); Text("Keep files within reach").font(.system(size: 10)).foregroundStyle(.secondary) }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).modifier(LiquidGlassStyle(shape: RoundedRectangle(cornerRadius: 18), active: true))
                Text("The notch opens two destinations: stash on the left and your pinned pipeline on the right.").font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Show the notch demo", action: onNotchDemo).buttonStyle(.bordered)
                Text("The demo does not enable background observers.").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }
    private var permissions: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 13) {
                Text("Make it feel like your Mac").font(.system(size: 19, weight: .semibold, design: .rounded))
                Text("Accessibility enables Finder keyboard gestures. File selection and practice drags work without it.").font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button(FileOrbitRuntime.isPreview ? "Open FileOrbit settings" : "Set up Accessibility", action: onSettings).buttonStyle(.borderedProminent)
                if FileOrbitRuntime.isPreview {
                    Text("This isolated preview keeps the installed app’s shortcut and login settings unchanged.").font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    Toggle("Launch at login", isOn: Binding(get: { loginEnabled }, set: { value in setLogin(value) }))
                        .toggleStyle(.switch).font(.system(size: 12))
                }
                Text("Screen Recording is not needed: FileOrbit works with files and images you provide.").font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(width: 305)
            VStack(alignment: .leading, spacing: 11) {
                Text("Drag modifiers").font(.system(size: 13, weight: .semibold))
                ForEach(OrbitMode.allCases) { mode in
                    Picker(mode.title, selection: Binding(get: { modifiers.trigger(for: mode) }, set: { modifiers.set(trigger: $0, for: mode) })) {
                        ForEach(ModifierTrigger.allCases) { trigger in Text("\(trigger.symbol)  \(trigger.title)").tag(trigger) }
                    }.font(.system(size: 11))
                }
                Text("Assigning a used key swaps the two modes. macOS may reserve Fn for another action.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Reset keys") { modifiers.reset() }.font(.system(size: 11))
            }.padding(16).modifier(LiquidGlassStyle(shape: RoundedRectangle(cornerRadius: 16)))
        }
    }
    private func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            error = SMAppService.mainApp.status == .requiresApproval ? "Allow FileOrbit in System Settings → Login Items." : nil
        } catch { loginEnabled = SMAppService.mainApp.status == .enabled; self.error = error.localizedDescription }
    }
    private func openSample(dragging: Bool) {
        guard let assets else { return }
        onSample(selectedSample == 0 ? assets.portrait : assets.deck, assets.outputDirectory, dragging)
    }
}

#if FILEORBIT_XCODE_PREVIEWS
#Preview("Onboarding · Daylight") {
    OnboardingSandboxView(assets: try? OnboardingSandboxAssets.create(), onSample: { _, _, _ in }, onNotchDemo: {}, onSettings: {}, onFinish: {})
        .preferredColorScheme(.light)
}
#Preview("Onboarding · Obsidian") {
    OnboardingSandboxView(assets: try? OnboardingSandboxAssets.create(), onSample: { _, _, _ in }, onNotchDemo: {}, onSettings: {}, onFinish: {})
        .preferredColorScheme(.dark)
}
#endif
