import Foundation

public enum DeveloperOperation: Sendable, Equatable {
    case convertData(StructuredFormat)
    case appIconset
    case minifySVG
    case extractPalette
    public var id: String {
        switch self {
        case .convertData(let format): return "developer-" + format.rawValue
        case .appIconset: return "app-iconset"
        case .minifySVG: return "minify-svg"
        case .extractPalette: return "color-palette"
        }
    }
    public var title: String {
        switch self {
        case .convertData(let format): return format.title
        case .appIconset: return "App Icons"
        case .minifySVG: return "Minify SVG"
        case .extractPalette: return "Palette"
        }
    }
    public var symbol: String {
        switch self {
        case .convertData(.swift): return "swift"
        case .convertData: return "curlybraces"
        case .appIconset: return "app.dashed"
        case .minifySVG: return "point.3.connected.trianglepath.dotted"
        case .extractPalette: return "paintpalette"
        }
    }
    public var subtitle: String {
        switch self {
        case .convertData(.swift): return "Generate a Codable schema"
        case .convertData(.csv): return "Flat records; CSV stores text"
        case .convertData(.yaml): return "Safe JSON-compatible YAML"
        case .convertData(.json): return "Structured UTF-8 data"
        case .appIconset: return "macOS 1×/2× icon asset set"
        case .minifySVG: return "Compact paths; exact coordinates"
        case .extractPalette: return "Swatch card + SwiftUI colors"
        }
    }
}

/// Local developer transformations use a snapshot and exclusive publication, just
/// like the existing converters. Arbitrary Swift, YAML tags and SVG scripts never run.
public struct DeveloperPayloadEngine: Sendable {
    public init() {}
    public static func availableOperations(for input: URL) -> [DeveloperOperation] {
        if let source = StructuredFormat.detect(input) { return StructuredFormat.allCases.filter { $0 != source }.map(DeveloperOperation.convertData) }
        if input.pathExtension.lowercased() == "svg" { return [.minifySVG] }
        if FileKind.detect(input) == .image { return [.appIconset, .extractPalette] }
        return []
    }
    public func run(input: URL, operation: DeveloperOperation, outputDirectory: URL? = nil,
                    cancellation: CancellationToken = CancellationToken()) throws -> ConversionResult {
        try cancellation.check()
        guard input.isFileURL else { throw ConversionError.invalidInput("Choose a local developer payload.") }
        let values = try input.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize, size > 0, size <= 67_108_864 else {
            throw ConversionError.invalidInput("Developer tools accept regular, nonempty files up to 64 MB. Structured text is limited to 8 MB.")
        }
        let destination = (outputDirectory ?? input.deletingLastPathComponent()).standardizedFileURL
        guard destination.isFileURL, try destination.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw ConversionError.invalidInput("Choose an existing local output folder.")
        }
        let original = try Data(contentsOf: input)
        guard original.count == size else { throw ConversionError.invalidInput("The source changed while it was being read. Try again after it finishes saving.") }
        let workspace = destination.appendingPathComponent(".fileorbit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: workspace) }
        let snapshot = workspace.appendingPathComponent("source." + input.pathExtension)
        try original.write(to: snapshot, options: [.withoutOverwriting])
        let outputs: [URL], note: String
        switch operation {
        case .convertData(let format):
            guard let sourceFormat = StructuredFormat.detect(input), sourceFormat != format else { throw ConversionError.unsupported("Choose a different structured-data format.") }
            let value = try StructuredDocument.read(original, format: sourceFormat)
            try cancellation.check()
            let encoded = try StructuredDocument.write(value, format: format)
            let output = workspace.appendingPathComponent("payload." + format.rawValue)
            try encoded.write(to: output, options: [.withoutOverwriting]); outputs = [output]
            if sourceFormat == .swift { note = "Generated a placeholder template from a declarative Swift schema. Original data values cannot be recovered from type definitions. No Swift code was executed." }
            else if format == .swift { note = "Generated Codable type definitions without source values. Optional fields reflect missing/null samples. Incompatible mixed types are rejected; inspect the generated schema before using it." }
            else if format == .csv { note = "CSV contains flat records as text; scalar type information is not retained. Nested values, missing fields and nulls are rejected." }
            else if sourceFormat == .csv { note = "CSV values are preserved as strings, including empty strings. No numbers, dates or booleans were guessed." }
            else { note = "Converted locally using a bounded JSON-compatible YAML subset. Numbers preserve their decimal spelling; duplicate keys and unsafe YAML features are rejected." }
        case .appIconset:
            outputs = [try DesignAssetTools.iconset(input: snapshot, workspace: workspace, cancellation: cancellation)]
            note = "Created a macOS AppIconset with ten valid 1×/2× slots from 16 to 1024 pixels. macOS does not define 3× icon slots. Drop the .appiconset folder into an Xcode asset catalog."
        case .extractPalette:
            outputs = try DesignAssetTools.palette(input: snapshot, workspace: workspace, cancellation: cancellation)
            note = "Dominant colors sampled locally in sRGB with alpha weighting. Saved a swatch PNG and hex/SwiftUI snippets; sampling is approximate and does not modify the source."
        case .minifySVG:
            guard input.pathExtension.lowercased() == "svg" else { throw ConversionError.unsupported("SVG minification requires an SVG file.") }
            let data = try SVGPathMinifier.minify(original), output = workspace.appendingPathComponent("artwork.svg")
            try data.write(to: output, options: [.withoutOverwriting]); outputs = [output]
            note = "Compacted path separators and removed XML comments without rounding coordinates. Static self-contained SVG only; the result is not guaranteed to be smaller than an already compact source."
        }
        try cancellation.check()
        let outputBytes = try outputs.reduce(Int64(0)) { try $0 + Self.byteCount($1) }
        guard outputBytes > 0 else { throw ConversionError.failed("The tool produced an empty output.") }
        // A complete source snapshot makes the operation deterministic. Refuse to
        // publish under the old name if a concurrent editor changed that source.
        let currentValues = try input.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard currentValues.isRegularFile == true, currentValues.isSymbolicLink != true, currentValues.fileSize == original.count,
              try Data(contentsOf: input) == original else { throw ConversionError.invalidInput("The original changed during processing. No output was published; try again with the updated file.") }
        // Establish the exact generated-file inventory while the directory is
        // still private. Enumerating after publication could include user files
        // inserted by an editor or watcher before the HUD captures its baseline.
        let undoNames: [String]?
        if operation == .appIconset {
            guard outputs.count == 1 else { throw ConversionError.failed("Invalid icon asset output.") }
            let files = try FileManager.default.contentsOfDirectory(at: outputs[0], includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            undoNames = try files.map { file in
                let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else { throw ConversionError.failed("Invalid generated icon asset.") }
                return file.lastPathComponent
            }.sorted()
        } else { undoNames = nil }
        try cancellation.check()
        let published = try OutputPublisher.publish(files: outputs, source: input, directory: destination, compressed: false)
        let undoFiles = undoNames.map { names in names.map { published[0].appendingPathComponent($0) } }
        return ConversionResult(outputURLs: published, inputBytes: Int64(original.count), outputBytes: outputBytes, note: note, undoURLs: undoFiles)
    }
    private static func byteCount(_ url: URL, depth: Int = 0) throws -> Int64 {
        guard depth <= 2 else { throw ConversionError.failed("Unexpected nested asset output.") }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isSymbolicLink != true else { throw ConversionError.failed("Unexpected symbolic link in generated output.") }
        if values.isDirectory == true {
            let children = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            guard !children.isEmpty, children.count <= 512 else { throw ConversionError.failed("Invalid generated asset directory.") }
            return try children.reduce(0) { try $0 + byteCount($1, depth: depth + 1) }
        }
        guard values.isRegularFile == true, let size = values.fileSize, size > 0 else { throw ConversionError.failed("A generated output is empty or invalid.") }
        return Int64(size)
    }
}
