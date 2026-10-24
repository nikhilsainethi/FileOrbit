import Foundation
import FileOrbitCore
import Darwin

func usage() {
    print("""
    FileOrbit — local file conversion
    Usage:
      fileorbit-cli INPUT --to png|jpg|heic|tiff|pdf|txt|docx [--output-dir DIRECTORY]
      fileorbit-cli INPUT --compress gentle|balanced|small [--output-dir DIRECTORY]
      fileorbit-cli --capabilities INPUT
      fileorbit-cli --engines
    Environment overrides: FILEORBIT_SOFFICE, FILEORBIT_QPDF, FILEORBIT_RESVG
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
        try printJSON(["libreoffice": environment.libreOfficeURL?.path ?? "missing", "qpdf": environment.qpdfURL?.path ?? "missing", "resvg": environment.resvgURL?.path ?? "missing"])
        exit(0)
    }
    if args.count == 2 && args[0] == "--capabilities" {
        let url = URL(fileURLWithPath: args[1])
        try printJSON(["kind": FileKind.detect(url).rawValue, "actions": CapabilityCatalog.actions(for: url, environment: environment).map { ["id": $0.id, "title": $0.title, "description": $0.subtitle] }])
        exit(0)
    }
    guard args.count == 3 || args.count == 5 else { usage(); exit(2) }
    let operation: FileOperation
    if args[1] == "--to", let format = OutputFormat(rawValue: args[2]) { operation = .convert(format) }
    else if args[1] == "--compress", let preset = CompressionPreset(rawValue: args[2]) { operation = .compress(preset) }
    else { usage(); exit(2) }
    var output: URL?
    if args.count == 5 {
        guard args[3] == "--output-dir" else { usage(); exit(2) }
        output = URL(fileURLWithPath: args[4], isDirectory: true)
    }
    let result = try ConversionEngine(environment: environment).run(ConversionRequest(input: URL(fileURLWithPath: args[0]), operation: operation, outputDirectory: output))
    var object: [String: Any] = ["outputs": result.outputURLs.map(\.path), "inputBytes": result.inputBytes, "outputBytes": result.outputBytes]
    if let note = result.note { object["note"] = note }
    try printJSON(object)
} catch {
    FileHandle.standardError.write(Data(("FileOrbit: \(error.localizedDescription)\n").utf8))
    exit(1)
}
