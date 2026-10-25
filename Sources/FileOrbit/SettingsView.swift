import SwiftUI
import AppKit
import ServiceManagement
import FileOrbitCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var settingsError: String?
    @ObservedObject private var preferences = StudioPreferences.shared
    @ObservedObject private var spatial = SpatialPreferences.shared
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Make yourself at home.").font(.system(size: 25, weight: .medium, design: .rounded))
                    Text("FileOrbit runs locally. No uploads, accounts, or telemetry.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                if !FileOrbitRuntime.isPreview {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("Appearance", selection: $preferences.appearance) {
                                Text("System").tag("system")
                                Text("Light").tag("light")
                                Text("Dark").tag("dark")
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: preferences.appearance) { _, value in
                                NSApp.appearance = FileOrbitRuntime.appearance(for: value)
                            }
                            Text("System follows macOS. Light uses clear quartz; Dark uses smoked glass and emerald accents.")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }.padding(12)
                    }
                }
                if FileOrbitRuntime.isPreview {
                    Label("Open a sample or drop files onto this preview. Double-tap Command stays with your installed FileOrbit.", systemImage: "eye")
                        .font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                } else {
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Double-tap Command", systemImage: "command").font(.headline)
                            Spacer()
                            status(model.accessibilityGranted)
                        }
                        Text("Select one file in Finder, then press and release ⌘ twice quickly. Other keys or mouse clicks cancel the gesture. Shortcuts such as ⌘C continue to work normally.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button(model.accessibilityGranted ? "Open Accessibility Settings" : "Enable in Accessibility") { model.requestAccessibility() }
                            Button("Refresh") { model.refresh() }
                        }
                        Text("macOS also asks for Finder Automation access the first time you invoke the shortcut. Choose file and drag-and-drop work without either permission.")
                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.padding(12)
                }
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Spatial companions", systemImage: "rectangle.topthird.inset.filled").font(.headline)
                        Toggle("Liquid Notch during Finder file drags", isOn: $spatial.notchEnabled)
                        Toggle("Show an orb for new clipboard images", isOn: $spatial.clipboardEnabled)
                        Toggle("Show an orb for new screenshot files", isOn: $spatial.screenshotEnabled)
                        Text("Optional, local observers. No clipboard history is saved. Sanitize always opens a review. Screenshot files stay unchanged; actions copy a new image.").font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Picker("Pinned pipeline", selection: $spatial.favoritePipelineID) {
                            ForEach(PinnedPipeline.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                        }
                        HStack {
                            Button("Preview Liquid Notch") { model.onNotchDemo?() }
                            Button("Practice in sandbox") { model.onOnboarding?() }
                        }
                        if FileOrbitRuntime.isPreview {
                            HStack {
                                Button("Try clipboard orb") { model.onOrbDemo?() }
                                Button("Preview quality loupe") { model.onLoupeDemo?() }
                            }
                            Text("Preview buttons use synthetic samples. Background observers stay off unless you enable them.").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }.font(.system(size: 12)).padding(12)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Local converters", systemImage: "shippingbox").font(.headline)
                        dependency("LibreOffice", description: "DOCX, PPTX and text document conversion", url: model.environment.libreOfficeURL, key: "FileOrbit.libreOfficePath")
                        Divider()
                        dependency("qpdf", description: "PDF compression and document metadata removal", url: model.environment.qpdfURL, key: "FileOrbit.qpdfPath")
                        Divider()
                        dependency("resvg", description: "SVG rendering", url: model.environment.resvgURL, key: "FileOrbit.resvgPath")
                        Divider()
                        dependency("cwebp", description: "WebP image encoding", url: model.environment.cwebpURL, key: "FileOrbit.cwebpPath")
                        Text("Image and basic PDF conversions use macOS. Converters are detected from this app, Applications, Homebrew, or a path you choose. Missing engines hide their actions.")
                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button("Check again") { model.refresh() }
                    }.padding(12)
                }
                if !FileOrbitRuntime.isPreview {
                Toggle("Launch FileOrbit when I log in", isOn: $loginEnabled)
                    .onChange(of: loginEnabled) { _, value in
                        do {
                            if value { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                        } catch {
                            loginEnabled = SMAppService.mainApp.status == .enabled
                            settingsError = "Could not change login behavior. Move FileOrbit to Applications first, then try again. \(error.localizedDescription)"
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Originals always stay intact.").font(.system(size: 12, weight: .medium))
                    Text("New files are saved beside the source. Compression saves a copy only when it is smaller. OCR, batch processing, and PDF redaction run locally. PDF-to-Office and animated/multipage image conversion are not included.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text("FileOrbit \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development") · Preview").font(.system(size: 10)).foregroundStyle(.tertiary).padding(.top, 8)
                }
            }.padding(28)
        }
        .frame(width: 550, height: 710)
        .onAppear { model.refresh() }
        .alert("Settings", isPresented: Binding(get: { settingsError != nil }, set: { if !$0 { settingsError = nil } })) { Button("OK") { settingsError = nil } } message: { Text(settingsError ?? "") }
    }
    private func status(_ available: Bool) -> some View {
        Label(available ? "Ready" : "Not enabled", systemImage: available ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 11)).foregroundStyle(available ? Color.teal : Color.secondary)
    }
    private func dependency(_ name: String, description: String, url: URL?, key: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(name).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(url == nil ? "Missing" : "Available").font(.system(size: 10)).foregroundStyle(url == nil ? .orange : .teal)
                Button("Locate…") { locate(key: key, name: name) }.font(.system(size: 11))
            }
            Text(description).font(.system(size: 11)).foregroundStyle(.secondary)
            if let url { Text(url.path).font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle).help(url.path) }
        }
    }
    private func locate(key: String, name: String) {
        let panel = NSOpenPanel()
        panel.title = "Locate \(name)"
        panel.message = name == "LibreOffice" ? "Choose LibreOffice.app or its soffice executable." : "Choose the \(name) executable."
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, var url = panel.url else { return }
            if name == "LibreOffice" && url.pathExtension == "app" { url.appendPathComponent("Contents/MacOS/soffice") }
            if FileManager.default.isExecutableFile(atPath: url.path) {
                UserDefaults.standard.set(url.path, forKey: key)
                model.refresh()
            } else { settingsError = "That selection is not an executable converter." }
        }
    }
}
