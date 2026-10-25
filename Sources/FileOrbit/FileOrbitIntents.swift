import AppIntents
import Foundation
import UniformTypeIdentifiers
import FileOrbitCore

enum IntentImageFormat: String, AppEnum {
    case png, jpg, heic, tiff, webp
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Image format" }
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] { [.png: "PNG", .jpg: "JPEG", .heic: "HEIC", .tiff: "TIFF", .webp: "WebP"] }
}
struct ConvertLocalImageIntent: AppIntent {
    static var title: LocalizedStringResource { "Convert Image Locally" }
    static var description: IntentDescription { "Convert an image on your Mac and return a new file. Original files are unchanged." }
    @Parameter(title: "Image") var image: IntentFile
    @Parameter(title: "Format", default: .png) var format: IntentImageFormat
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let result = try await IntentProcessingActor().run(image, operation: .convert(OutputFormat(rawValue: format.rawValue)!))
        return .result(value: result)
    }
}
struct CompressLocalImageIntent: AppIntent {
    static var title: LocalizedStringResource { "Compress Image Locally" }
    static var description: IntentDescription { "Return a smaller image using FileOrbit’s balanced preset. Reports when the source is already compact." }
    @Parameter(title: "Image") var image: IntentFile
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        .result(value: try await IntentProcessingActor().run(image, operation: .compress(.balanced)))
    }
}
struct LiftLocalSubjectIntent: AppIntent {
    static var title: LocalizedStringResource { "Lift Subject Locally" }
    static var description: IntentDescription { "Use on-device Apple Vision to return foreground subjects as a transparent PNG." }
    @Parameter(title: "Image") var image: IntentFile
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        .result(value: try await IntentProcessingActor().run(image, operation: nil))
    }
}
struct FileOrbitShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ConvertLocalImageIntent(), phrases: ["Convert an image with \(.applicationName)"], shortTitle: "Convert Image", systemImageName: "arrow.triangle.2.circlepath")
        AppShortcut(intent: CompressLocalImageIntent(), phrases: ["Compress an image with \(.applicationName)"], shortTitle: "Compress Image", systemImageName: "arrow.down.right.and.arrow.up.left")
        AppShortcut(intent: LiftLocalSubjectIntent(), phrases: ["Lift a subject with \(.applicationName)"], shortTitle: "Lift Subject", systemImageName: "person.crop.rectangle")
    }
}
private actor IntentProcessingActor {
    func run(_ file: IntentFile, operation: FileOperation?) async throws -> IntentFile {
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent("fileorbit-intent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: workspace) }
        let ext = URL(fileURLWithPath: file.filename).pathExtension.lowercased()
        guard ["png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "webp", "bmp"].contains(ext) else { throw ConversionError.unsupported("Choose a supported raster image.") }
        let source = workspace.appendingPathComponent("input." + ext)
        if let url = file.fileURL {
            let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let properties = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard url.isFileURL, properties.isRegularFile == true, properties.isSymbolicLink != true, let count = properties.fileSize, count > 0, count <= 128_000_000 else { throw ConversionError.invalidInput("Shortcuts images must be regular files up to 128 MB.") }
            try FileManager.default.copyItem(at: url, to: source)
        } else {
            let data = file.data
            guard !data.isEmpty, data.count <= 128_000_000 else { throw ConversionError.invalidInput("Shortcuts images must be nonempty and no larger than 128 MB.") }
            try data.write(to: source)
        }
        try Task.checkCancellation()
        let token = CancellationToken()
        let result = try await withTaskCancellationHandler {
            if let operation { return try ConversionEngine(environment: .discover()).run(ConversionRequest(input: source, operation: operation, outputDirectory: workspace), cancellation: token) }
            return try await NeuralProcessingActor().liftSubject(input: source, output: .transparentPNG, outputDirectory: workspace, cancellation: token)
        } onCancel: { token.cancel() }
        let output = result.outputURLs[0]
        guard result.outputBytes <= 256_000_000 else { throw ConversionError.unsupported("The result is too large for a Shortcuts transfer. Use the wheel to save it directly.") }
        let data = try Data(contentsOf: output)
        try Task.checkCancellation()
        let category: ImpactCategory = operation == nil ? .isolation : { if case .compress = operation { return .compression }; return .conversion }()
        await MainActor.run { ImpactStore.shared.record(id: UUID(), category: category, inputBytes: result.inputBytes, outputBytes: result.outputBytes) }
        return IntentFile(data: data, filename: "FileOrbit." + output.pathExtension, type: UTType(filenameExtension: output.pathExtension))
    }
}
