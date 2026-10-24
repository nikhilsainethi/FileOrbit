import Foundation
import ImageIO
import CoreGraphics
import PDFKit

enum MetadataScrubber {
    static func scrub(input: URL, environment: EngineEnvironment, workspace: URL, cancellation: CancellationToken) throws -> [URL] {
        try cancellation.check()
        if FileKind.detect(input) == .image {
            // Rebuild from oriented pixels; no source EXIF/IPTC/GPS/XMP dictionaries are copied.
            // PNG avoids a second lossy encode of a JPEG or HEIC source.
            let image = try NativeConverter.decodedImage(input)
            let output = workspace.appendingPathComponent("metadata-removed.png")
            try NativeConverter.encode(image, to: output, format: .png, quality: 1)
            return [output]
        }
        guard FileKind.detect(input) == .pdf else { throw ConversionError.unsupported("Metadata removal supports images and PDF documents.") }
        let original = try PDFSafety.modifiableDocument(input)
        guard let qpdf = environment.qpdfURL else { throw ConversionError.missingDependency("Install qpdf to remove PDF document metadata locally.") }
        // --remove-info alone retains /ModDate. A bounded trailer-only JSON update removes
        // the entire /Info entry, and --remove-metadata removes the catalog's XMP stream.
        let json = try LocalProcess.run(executable: qpdf, arguments: ["--json-output=2", "--json-object=trailer", input.path], cancellation: cancellation, directory: workspace)
        guard var root = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              var objects = root["qpdf"] as? [Any], objects.count == 2,
              var table = objects[1] as? [String: Any], var trailer = table["trailer"] as? [String: Any],
              var value = trailer["value"] as? [String: Any] else {
            throw ConversionError.failed("The PDF metadata could not be inspected safely.")
        }
        value.removeValue(forKey: "/Info")
        // qpdf otherwise preserves the original first trailer ID even with --deterministic-id.
        // Remove both source IDs so the rewrite generates identifiers from the cleaned content.
        value.removeValue(forKey: "/ID")
        trailer["value"] = value; table["trailer"] = trailer; objects[1] = table; root["qpdf"] = objects
        let update = workspace.appendingPathComponent("remove-info.json")
        try JSONSerialization.data(withJSONObject: root).write(to: update, options: .atomic)
        let output = workspace.appendingPathComponent("metadata-removed.pdf")
        _ = try LocalProcess.run(executable: qpdf, arguments: [input.path, "--update-from-json=\(update.path)", "--remove-metadata", "--deterministic-id", output.path], cancellation: cancellation, directory: workspace)
        _ = try LocalProcess.run(executable: qpdf, arguments: ["--check", output.path], cancellation: cancellation, directory: workspace)
        guard let document = PDFDocument(url: output), document.pageCount == original.pageCount, document.string == original.string,
              let reference = CGPDFDocument(output as CFURL), reference.info == nil,
              let catalog = reference.catalog else { throw ConversionError.failed("The scrubbed PDF failed metadata or content validation.") }
        var metadata: CGPDFObjectRef?
        guard !CGPDFDictionaryGetObject(catalog, "Metadata", &metadata) else { throw ConversionError.failed("The output PDF still contains document metadata.") }
        return [output]
    }
}
