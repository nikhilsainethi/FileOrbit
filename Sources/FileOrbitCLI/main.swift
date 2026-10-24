import Foundation
import FileOrbitCore
import Darwin

func usage() {
    print("""
    FileOrbit — local file conversion
    Usage:
      fileorbit-cli INPUT --to png|jpg|heic|tiff|webp|pdf|txt|docx [--pdf-mode firstPage|allPages|mergedTallImage] [--output-dir DIRECTORY]
      fileorbit-cli INPUT --compress gentle|balanced|small [--output-dir DIRECTORY]
      fileorbit-cli INPUT --split|--ocr|--scrub-metadata [--output-dir DIRECTORY]
      fileorbit-cli INPUT --redact-regions REGIONS.json [--output-dir DIRECTORY]
      fileorbit-cli --capabilities INPUT
      fileorbit-cli --engines
    Redaction JSON: [{"pageIndex":0,"x":0.1,"y":0.1,"width":0.2,"height":0.1}]
    Regions use normalized top-left coordinates of the displayed/rotated page.
    Environment overrides: FILEORBIT_SOFFICE, FILEORBIT_QPDF, FILEORBIT_RESVG, FILEORBIT_CWEBP
    Originals are never overwritten. Compression retains only smaller valid results.
    """)
}
func printJSON(_ object: Any) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    print(String(decoding: data, as: UTF8.self))
}
let args = Array(CommandLine.arguments.dropFirst())
let environment = EngineEnvironment.discover()
do {
    if args == ["--help"] || args == ["-h"] || args.isEmpty { usage(); exit(args.isEmpty ? 2 : 0) }
    if args == ["--engines"] {
        try printJSON(["libreoffice": environment.libreOfficeURL?.path ?? "missing", "qpdf": environment.qpdfURL?.path ?? "missing", "resvg": environment.resvgURL?.path ?? "missing", "cwebp": environment.cwebpURL?.path ?? "missing"])
        exit(0)
    }
    if args.count == 2 && args[0] == "--capabilities" {
        let url = URL(fileURLWithPath: args[1])
        try printJSON(["kind": FileKind.detect(url).rawValue, "actions": CapabilityCatalog.actions(for: url, environment: environment).map { ["id": $0.id, "title": $0.title, "description": $0.subtitle] }, "modifications": CapabilityCatalog.modificationActions(for: url, environment: environment).map { ["id": $0.id, "title": $0.title, "description": $0.subtitle] }])
        exit(0)
    }
    guard args.count >= 2 else { usage(); exit(2) }
    var operation: FileOperation
    var next = 2
    switch args[1] {
    case "--to":
        guard args.count > 2, let format = OutputFormat(rawValue: args[2]) else { usage(); exit(2) }
        operation = .convert(format); next = 3
    case "--compress":
        guard args.count > 2, let preset = CompressionPreset(rawValue: args[2]) else { usage(); exit(2) }
        operation = .compress(preset); next = 3
    case "--split": operation = .splitPDF
    case "--ocr": operation = .ocrText
    case "--scrub-metadata": operation = .scrubMetadata
    case "--redact-regions":
        guard args.count > 2 else { usage(); exit(2) }
        let data = try Data(contentsOf: URL(fileURLWithPath: args[2]))
        guard data.count <= 2_000_000, let entries = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ConversionError.invalidInput("Redaction regions must be a JSON array smaller than 2 MB.")
        }
        let regions = try entries.map { entry -> RedactionRegion in
            guard let page = entry["pageIndex"] as? Int, let x = entry["x"] as? Double, let y = entry["y"] as? Double,
                  let width = entry["width"] as? Double, let height = entry["height"] as? Double else {
                throw ConversionError.invalidInput("Each region needs pageIndex, x, y, width and height.")
            }
            return .init(pageIndex: page, normalizedRect: CGRect(x: x, y: y, width: width, height: height))
        }
        operation = .redactPDF(regions); next = 3
    default: usage(); exit(2)
    }
    var output: URL?
    while next < args.count {
        guard next + 1 < args.count else { usage(); exit(2) }
        if args[next] == "--output-dir", output == nil { output = URL(fileURLWithPath: args[next + 1], isDirectory: true) }
        else if args[next] == "--pdf-mode", let mode = PDFExportMode(rawValue: args[next + 1]), case .convert(let format) = operation {
            operation = .exportPDF(format, mode)
        } else { usage(); exit(2) }
        next += 2
    }
    let result = try ConversionEngine(environment: environment).run(ConversionRequest(input: URL(fileURLWithPath: args[0]), operation: operation, outputDirectory: output))
    var object: [String: Any] = ["outputs": result.outputURLs.map(\.path), "inputBytes": result.inputBytes, "outputBytes": result.outputBytes]
    if let note = result.note { object["note"] = note }
    try printJSON(object)
} catch {
    FileHandle.standardError.write(Data(("FileOrbit: \(error.localizedDescription)\n").utf8))
    exit(1)
}
