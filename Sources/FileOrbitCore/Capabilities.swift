import Foundation
import ImageIO
import UniformTypeIdentifiers

public extension FileKind {
    static func detect(_ url: URL) -> FileKind {
        guard url.isFileURL else { return .unsupported }
        if let values = try? url.resourceValues(forKeys: [.isDirectoryKey]), values.isDirectory == true {
            return .unsupported
        }
        switch url.pathExtension.lowercased() {
        case "pdf": return .pdf
        case "docx": return .docx
        case "pptx": return .pptx
        case "txt": return .text
        case "svg": return .svg
        default:
            guard let type = UTType(filenameExtension: url.pathExtension.lowercased()), type.conforms(to: .image) else {
                return .unsupported
            }
            let readable = CGImageSourceCopyTypeIdentifiers() as! [String]
            return readable.contains(type.identifier) ? .image : .unsupported
        }
    }
}

public enum CapabilityCatalog {
    public static var nativeOutputFormats: [OutputFormat] {
        let writable = Set(CGImageDestinationCopyTypeIdentifiers() as! [String])
        return [OutputFormat.png, .jpg, .heic, .tiff].filter { writable.contains(identifier(for: $0)) }
    }

    public static func actions(for url: URL, environment: EngineEnvironment) -> [FileAction] {
        switch FileKind.detect(url) {
        case .image:
            guard !hasMultipleFrames(url) else { return [] }
            let sourceFormat = format(for: url.pathExtension)
            var actions = (nativeOutputFormats.filter { $0 != sourceFormat } + [.pdf]).map(convertAction)
            if let sourceFormat, nativeOutputFormats.contains(sourceFormat) { actions.append(compressAction) }
            return actions
        case .pdf:
            return [.png, .jpg, .txt].map(convertAction) + (environment.qpdfURL == nil ? [] : [compressAction])
        case .docx:
            return (environment.libreOfficeURL == nil ? [] : [.pdf, .txt].map(convertAction)) + [compressAction]
        case .pptx:
            return environment.libreOfficeURL == nil ? [] : [.pdf, .png, .jpg].map(convertAction)
        case .text:
            return environment.libreOfficeURL == nil ? [] : [.pdf, .docx].map(convertAction)
        case .svg:
            return environment.resvgURL == nil ? [] : [.png, .jpg].map(convertAction)
        case .unsupported:
            return []
        }
    }

    public static func unavailableReason(for url: URL, environment: EngineEnvironment) -> String? {
        switch FileKind.detect(url) {
        case .image where hasMultipleFrames(url):
            return "Animated and multi-page images are not supported yet. No frames will be discarded."
        case .pdf where environment.qpdfURL == nil:
            return "Install qpdf to enable PDF compression. Image and text exports work without it."
        case .docx where environment.libreOfficeURL == nil:
            return "Install LibreOffice to convert this document. Embedded-image compression is available now."
        case .pptx, .text:
            return environment.libreOfficeURL == nil ? "Install LibreOffice to convert this file locally." : nil
        case .svg:
            return environment.resvgURL == nil ? "Install resvg to render SVG files locally." : nil
        case .unsupported:
            return "Choose a supported image, PDF, DOCX, PPTX, TXT, or SVG file."
        default:
            return nil
        }
    }

    private static func hasMultipleFrames(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return false }
        return CGImageSourceGetCount(source) > 1
    }

    private static func format(for ext: String) -> OutputFormat? {
        switch ext.lowercased() {
        case "png": return .png
        case "jpg", "jpeg", "jpe": return .jpg
        case "heic", "heif": return .heic
        case "tiff", "tif": return .tiff
        default: return nil
        }
    }

    private static func identifier(for format: OutputFormat) -> String {
        switch format {
        case .png: return UTType.png.identifier
        case .jpg: return UTType.jpeg.identifier
        case .heic: return UTType.heic.identifier
        case .tiff: return UTType.tiff.identifier
        default: return ""
        }
    }

    private static func convertAction(_ format: OutputFormat) -> FileAction {
        let description: String
        let symbol: String
        switch format {
        case .png: description = "Lossless image"; symbol = "photo"
        case .jpg: description = "JPEG image"; symbol = "photo.fill"
        case .heic: description = "Efficient image"; symbol = "photo.stack"
        case .tiff: description = "TIFF image"; symbol = "square.stack.3d.up"
        case .pdf: description = "PDF document"; symbol = "doc.richtext"
        case .txt: description = "Extract text"; symbol = "text.alignleft"
        case .docx: description = "Word document"; symbol = "doc.text"
        }
        return FileAction(id: "convert-" + format.rawValue, title: format.rawValue.uppercased(), subtitle: description, symbol: symbol, operation: .convert(format))
    }

    private static var compressAction: FileAction {
        FileAction(id: "compress", title: "Compress", subtitle: "Reduce file size", symbol: "arrow.down.right.and.arrow.up.left", operation: .compress(.balanced))
    }
}
