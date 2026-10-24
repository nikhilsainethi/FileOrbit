import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

public enum DocxCompressor {
    public static func compress(input: URL, preset: CompressionPreset, workspace: URL,
                                cancellation: CancellationToken) throws -> [URL] {
        let extracted = workspace.appendingPathComponent("docx-package-\(UUID().uuidString)", isDirectory: true)
        try OfficePackage.unpack(input: input, into: extracted, cancellation: cancellation, rejectActiveContent: false)
        defer { try? FileManager.default.removeItem(at: extracted) }
        guard FileManager.default.fileExists(atPath: extracted.appendingPathComponent("word/document.xml").path) else {
            throw ConversionError.invalidInput("This is not a valid Word DOCX document.")
        }
        let paths = try FileManager.default.subpathsOfDirectory(atPath: extracted.path)
        if paths.contains(where: { $0.lowercased().hasPrefix("_xmlsignatures/") }) {
            throw ConversionError.unsupported("Digitally signed DOCX files cannot be compressed without invalidating the signature. Use an unsigned copy.")
        }
        let longest: Int
        let quality: Double
        switch preset { case .gentle: longest = 2400; quality = 0.88
        case .balanced: longest = 1600; quality = 0.72
        case .small: longest = 1000; quality = 0.55 }
        for path in paths where path.hasPrefix("word/media/") {
            try cancellation.check()
            let imageURL = extracted.appendingPathComponent(path)
            let ext = imageURL.pathExtension.lowercased()
            guard ["jpg", "jpeg", "png"].contains(ext) else { continue }
            guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil), CGImageSourceGetCount(source) == 1,
                  let type = CGImageSourceGetType(source),
                  [UTType.jpeg.identifier, UTType.png.identifier].contains(type as String),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 40000, height <= 40000,
                  Int64(width) * Int64(height) <= 100_000_000 else { continue }
            // Keep EXIF orientation in metadata and do not rotate twice inside the Word drawing.
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                           kCGImageSourceThumbnailMaxPixelSize: min(max(width, height), longest),
                                           kCGImageSourceCreateThumbnailWithTransform: false,
                                           kCGImageSourceShouldCacheImmediately: true]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { continue }
            let temporary = imageURL.deletingLastPathComponent().appendingPathComponent(".optimized-\(UUID().uuidString).\(ext)")
            defer { try? FileManager.default.removeItem(at: temporary) }
            guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL, type, 1, nil) else { continue }
            var outputProperties = properties
            outputProperties[kCGImageDestinationLossyCompressionQuality] = quality
            outputProperties[kCGImagePropertyPixelWidth] = image.width
            outputProperties[kCGImagePropertyPixelHeight] = image.height
            CGImageDestinationAddImage(destination, image, outputProperties as CFDictionary)
            guard CGImageDestinationFinalize(destination),
                  let check = CGImageSourceCreateWithURL(temporary as CFURL, nil), CGImageSourceGetCount(check) == 1,
                  CGImageSourceCreateImageAtIndex(check, 0, nil) != nil else { continue }
            let oldSize = (try imageURL.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
            let newSize = (try temporary.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? oldSize
            if newSize > 0 && newSize < oldSize {
                try FileManager.default.removeItem(at: imageURL)
                try FileManager.default.moveItem(at: temporary, to: imageURL)
            }
        }
        try cancellation.check()
        let output = workspace.appendingPathComponent("compressed.docx")
        guard !FileManager.default.fileExists(atPath: output.path) else { throw ConversionError.failed("Temporary output already exists.") }
        _ = try LocalProcess.run(executable: URL(fileURLWithPath: "/usr/bin/zip"), arguments: ["-q", "-9", "-r", output.path, "."], timeout: 120, cancellation: cancellation, directory: extracted)
        try OfficePackage.validateArchive(output)
        return [output]
    }
}

/// Restrictive OOXML ZIP preflight. Validation happens before invoking any extractor.
enum OfficePackage {
    private static let maxExpanded: UInt64 = 512 * 1024 * 1024
    static func validateArchive(_ input: URL) throws {
        let size = (try input.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
        guard size > 21 && size <= 256 * 1024 * 1024 else { throw ConversionError.invalidInput("Office packages must be nonempty and smaller than 256 MB.") }
        let data = try Data(contentsOf: input, options: .mappedIfSafe)
        func u16(_ offset: Int) throws -> UInt16 {
            guard offset >= 0, offset + 2 <= data.count else { throw invalidZIP() }
            return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
        }
        func u32(_ offset: Int) throws -> UInt32 { UInt32(try u16(offset)) | (UInt32(try u16(offset + 2)) << 16) }
        func validateExtra(_ offset: Int, length: Int) throws {
            var cursor = offset
            let end = offset + length
            guard end <= data.count else { throw invalidZIP() }
            while cursor < end {
                guard cursor + 4 <= end else { throw invalidZIP() }
                let tag = try u16(cursor), size = Int(try u16(cursor + 2))
                // ZIP64 and alternate Unicode path fields require separate interpretation; reject instead of letting an extractor choose another path.
                guard tag != 0x0001, tag != 0x7075, cursor + 4 + size <= end else { throw invalidZIP() }
                cursor += 4 + size
            }
        }
        var end: Int?
        for offset in stride(from: data.count - 22, through: max(0, data.count - 65557), by: -1) {
            if try u32(offset) == 0x06054b50, offset + 22 + Int(try u16(offset + 20)) == data.count { end = offset; break }
        }
        guard let end, try u16(end + 4) == 0, try u16(end + 6) == 0 else { throw invalidZIP() }
        let count = Int(try u16(end + 10))
        guard count > 0, count <= 10000, count == Int(try u16(end + 8)) else { throw invalidZIP() }
        let centralSize = Int(try u32(end + 12)), centralStart = Int(try u32(end + 16))
        guard centralStart > 0, centralSize > 0, centralStart <= end, centralSize <= end - centralStart else { throw invalidZIP() }
        var cursor = centralStart, expanded: UInt64 = 0
        var seen = Set<String>()
        var ranges: [(Int, Int)] = []
        for _ in 0..<count {
            guard try u32(cursor) == 0x02014b50 else { throw invalidZIP() }
            let flags = try u16(cursor + 8), method = try u16(cursor + 10)
            let compressed = UInt64(try u32(cursor + 20)), uncompressed = UInt64(try u32(cursor + 24))
            let nameLength = Int(try u16(cursor + 28)), extraLength = Int(try u16(cursor + 30)), commentLength = Int(try u16(cursor + 32))
            let attributes = try u32(cursor + 38), local = Int(try u32(cursor + 42))
            let next = cursor + 46 + nameLength + extraLength + commentLength
            guard flags & 1 == 0, [0, 8].contains(method), nameLength > 0, next <= centralStart + centralSize,
                  uncompressed <= 128 * 1024 * 1024, compressed <= UInt64(data.count),
                  try u16(cursor + 34) == 0 else { throw invalidZIP() }
            let nameBytes = data[(cursor + 46)..<(cursor + 46 + nameLength)]
            guard let name = String(data: nameBytes, encoding: .utf8), safeName(name) else { throw invalidZIP() }
            try validateExtra(cursor + 46 + nameLength, length: extraLength)
            let key = name.precomposedStringWithCanonicalMapping.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard seen.insert(key).inserted else { throw invalidZIP() }
            let unixType = (attributes >> 16) & 0xf000
            guard unixType == 0 || unixType == 0x8000 || unixType == 0x4000 else { throw invalidZIP() }
            expanded += uncompressed
            guard expanded <= maxExpanded else { throw ConversionError.unsupported("This Office package expands beyond the 512 MB processing limit.") }
            guard local >= 0, local + 30 < centralStart, try u32(local) == 0x04034b50,
                  try u16(local + 6) == flags, try u16(local + 8) == method else { throw invalidZIP() }
            let localNameLength = Int(try u16(local + 26)), localExtra = Int(try u16(local + 28))
            let payload = local + 30 + localNameLength + localExtra
            guard localNameLength == nameLength, payload <= centralStart,
                  data[(local + 30)..<(local + 30 + localNameLength)] == nameBytes,
                  compressed <= UInt64(centralStart - payload) else { throw invalidZIP() }
            try validateExtra(local + 30 + localNameLength, length: localExtra)
            ranges.append((local, payload + Int(compressed)))
            cursor = next
        }
        guard cursor == centralStart + centralSize else { throw invalidZIP() }
        ranges.sort { $0.0 < $1.0 }
        for index in 1..<ranges.count { guard ranges[index].0 >= ranges[index - 1].1 else { throw invalidZIP() } }
        guard seen.contains("[content_types].xml") else { throw ConversionError.invalidInput("The file does not contain a valid Office package.") }
    }
    static func unpack(input: URL, into folder: URL, cancellation: CancellationToken, rejectActiveContent: Bool) throws {
        try cancellation.check()
        let values = try input.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let inputSize = values.fileSize, inputSize > 21, inputSize <= 256 * 1024 * 1024 else {
            throw ConversionError.unsupported("Office packages must be regular files smaller than 256 MB.")
        }
        let snapshot = folder.deletingLastPathComponent().appendingPathComponent(".office-snapshot-\(UUID().uuidString).zip")
        try FileManager.default.copyItem(at: input, to: snapshot)
        defer { try? FileManager.default.removeItem(at: snapshot) }
        try validateArchive(snapshot)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        _ = try LocalProcess.run(executable: URL(fileURLWithPath: "/usr/bin/unzip"), arguments: ["-qq", snapshot.path, "-d", folder.path], timeout: 60, cancellation: cancellation)
        let entries = try FileManager.default.subpathsOfDirectory(atPath: folder.path)
        var total: UInt64 = 0
        for path in entries {
            try cancellation.check()
            let url = folder.appendingPathComponent(path)
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey, .fileSizeKey])
            guard values.isSymbolicLink != true, values.isRegularFile == true || values.isDirectory == true else { throw invalidZIP() }
            total += UInt64(max(0, values.fileSize ?? 0))
            guard total <= maxExpanded else { throw invalidZIP() }
            if rejectActiveContent { try inspectOfficePart(url: url, relativePath: path, isFile: values.isRegularFile == true) }
        }
    }
    private static func safeName(_ name: String) -> Bool {
        guard !name.hasPrefix("/"), !name.contains("\\"), !name.contains("\0"), !name.contains(":"),
              !name.hasPrefix("__MACOSX/"), !name.unicodeScalars.contains(where: { $0.value < 32 }) else { return false }
        var components = name.components(separatedBy: "/")
        if components.last == "" { components.removeLast() }
        return !components.isEmpty && components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
    private static func invalidZIP() -> ConversionError { .invalidInput("The Office package is damaged, encrypted, too large, or contains unsafe archive entries. It was not extracted.") }
    private static func inspectOfficePart(url: URL, relativePath: String, isFile: Bool) throws {
        let path = relativePath.lowercased()
        guard !path.contains("vbaproject"), !path.contains("/activex/"), !path.contains("/embeddings/"), !path.contains("/externallinks/") else {
            throw ConversionError.unsupported("Office files with macros, embedded objects, or linked external content are not supported.")
        }
        guard isFile, path.hasSuffix(".xml") || path.hasSuffix(".rels") else { return }
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard (values.fileSize ?? 0) <= 16 * 1024 * 1024 else { throw ConversionError.unsupported("An Office XML part exceeds the 16 MB processing limit.") }
        let data = try Data(contentsOf: url)
        guard let xml = String(data: data, encoding: .utf8) else { throw ConversionError.unsupported("This Office file uses an unsupported XML encoding.") }
        let lower = xml.lowercased()
        guard !lower.contains("<!doctype"), !lower.contains("<!entity"), !lower.contains("macroenabled"),
              !lower.contains("ddeauto"), !lower.contains("includetext"), !lower.contains("includepicture") else {
            throw ConversionError.unsupported("This Office file contains active or externally loaded content and cannot be converted locally by FileOrbit.")
        }
        if path.hasSuffix(".rels") {
            let delegate = RelationshipInspector()
            let parser = XMLParser(data: data)
            parser.shouldResolveExternalEntities = false
            parser.delegate = delegate
            guard parser.parse(), !delegate.hasExternalResource else {
                throw ConversionError.unsupported("This Office file links to an external resource. Embed the resource before converting.")
            }
        }
    }
}

private final class RelationshipInspector: NSObject, XMLParserDelegate {
    var hasExternalResource = false
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        if elementName.split(separator: ":").last == "Relationship", attributeDict["TargetMode"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "external",
           !(attributeDict["Type"] ?? "").lowercased().hasSuffix("/hyperlink") { hasExternalResource = true }
    }
}
