import SwiftUI
import AppKit
import ServiceManagement
import FileOrbitCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var settingsError: String?
    @AppStorage("FileOrbit.appearance") private var appearance = "system"
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
                            Picker("Appearance", selection: $appearance) {
                                Text("System").tag("system")
                                Text("Light").tag("light")
                                Text("Dark").tag("dark")
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: appearance) { _, value in
                                NSApp.appearance = FileOrbitRuntime.appearance(for: value)
                            }
                            Text("Dark uses the graphite and smoky-lavender palette. This changes FileOrbit only.")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }.padding(12)
                    }
                }
                if FileOrbitRuntime.isPreview {
                    Label("This preview uses Choose File. Double-tap Command stays with your installed FileOrbit.", systemImage: "eye")
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
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Local converters", systemImage: "shippingbox").font(.headline)
                        dependency("LibreOffice", description: "DOCX, PPTX and text document conversion", url: model.environment.libreOfficeURL, key: "FileOrbit.libreOfficePath")
                        Divider()
                        dependency("qpdf", description: "PDF compression", url: model.environment.qpdfURL, key: "FileOrbit.qpdfPath")
                        Divider()
                        dependency("resvg", description: "SVG rendering", url: model.environment.resvgURL, key: "FileOrbit.resvgPath")
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
                    Text("New files are saved beside the source. Compression saves a copy only when it is smaller. PDF-to-Office, OCR, animated/multipage image conversion, and batch conversion are not included in this preview.")
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
