import Foundation
import Dispatch
import Vision
import CoreImage
import CoreML
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import PDFKit
import CryptoKit

public enum SubjectOutput: String, CaseIterable, Sendable { case transparentPNG, whiteBackdrop }
public enum SanitizeStyle: String, CaseIterable, Sendable {
    case frosted, obsidian
    public var title: String { self == .frosted ? "Frosted Glass" : "Solid Obsidian" }
}
public struct PrivacyDetection: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let kind: PrivacyKind
    public let region: RedactionRegion
    public init(id: UUID = UUID(), kind: PrivacyKind, region: RedactionRegion) { self.id = id; self.kind = kind; self.region = region }
}
public struct SanitizePage: Sendable {
    public let pngData: Data
    public let pointSize: CGSize
    public let pixelSize: CGSize
}
public struct SanitizeDocument: Sendable {
    public let input: URL
    public let sourceDigest: Data
    public let inputBytes: Int64
    public let isPDF: Bool
    public let pages: [SanitizePage]
    public let detections: [PrivacyDetection]
}

/// Vision requests and Core Image state never cross this actor. Review snapshots contain only
/// bounded encoded pixels, geometry and category labels; OCR strings are not stored or logged.
public actor NeuralProcessingActor {
    // Vision's synchronous API can wait for Swift tasks internally. Keep those
    // calls off the cooperative pool so concurrent inspections cannot exhaust it.
    // One shared serial queue also bounds native model work across actor instances.
    private static let workQueue = DispatchSerialQueue(label: "io.fileorbit.neural", qos: .userInitiated)
    public nonisolated var unownedExecutor: UnownedSerialExecutor { Self.workQueue.asUnownedSerialExecutor() }

    public static let maximumPages = 100
    public static let maximumSnapshotPixels = 64_000_000
    public static let maximumSnapshotBytes = 134_217_728
    private let context = CIContext(options: [.cacheIntermediates: false])
    public init() {}

    public func liftSubject(input: URL, output: SubjectOutput, outputDirectory: URL? = nil,
                            cancellation: CancellationToken = CancellationToken()) throws -> ConversionResult {
        try cancellation.check()
        let count = try Self.validateInput(input)
        guard FileKind.detect(input) == .image else { throw ConversionError.unsupported("Lift Subject requires a single-frame image.") }
        let digest = try Self.digest(input, cancellation: cancellation)
        let image = try NativeConverter.decodedImage(input, maxDimension: 4096)
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()
        do { try handler.perform([request]) }
        catch { try cancellation.check(); throw ConversionError.failed("Local subject isolation could not run on this image: \(error.localizedDescription)") }
        try cancellation.check()
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            throw ConversionError.unsupported("No foreground subject was found. Try a clear photo with a distinct subject.")
        }
        let pixels = try observation.generateMaskedImage(ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: false)
        let isolated = CIImage(cvPixelBuffer: pixels)
        guard let rendered = context.createCGImage(isolated, from: isolated.extent) else { throw ConversionError.failed("Could not render the isolated subject.") }
        let prepared = output == .whiteBackdrop ? try NativeConverter.whiteBackground(rendered) : rendered
        let directory = try Self.outputDirectory(outputDirectory, input: input)
        let workspace = try Self.workspace(in: directory)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let file = workspace.appendingPathComponent("subject.png")
        try Self.encodeCleanPNG(prepared, to: file)
        try Self.requireUnchanged(input, digest: digest, cancellation: cancellation)
        return try Self.publish(file, input: input, inputBytes: count, directory: directory,
                                note: "Isolated locally with Apple Vision at up to 4,096 pixels per side. Check hair, edges and transparent details before sharing.", cancellation: cancellation)
    }

    public func inspect(input: URL, cancellation: CancellationToken = CancellationToken()) throws -> SanitizeDocument {
        try cancellation.check()
        let count = try Self.validateInput(input)
        let originalDigest = try Self.digest(input, cancellation: cancellation)
        let isPDF = FileKind.detect(input) == .pdf
        var pages: [SanitizePage] = [], detections: [PrivacyDetection] = []
        var totalPixels = 0, totalBytes = 0
        func append(_ image: CGImage, size: CGSize) throws {
            try cancellation.check()
            guard image.width <= (Self.maximumSnapshotPixels - totalPixels) / image.height else {
                throw ConversionError.unsupported("This document exceeds the 64-megapixel Sanitize review limit. Split it into smaller documents first.")
            }
            let data = try Self.png(image)
            guard data.count <= Self.maximumSnapshotBytes - totalBytes else {
                throw ConversionError.unsupported("This document exceeds the 128 MB Sanitize preview limit. Split it into smaller documents first.")
            }
            let pageIndex = pages.count
            detections.append(contentsOf: try Self.recognize(image, pageIndex: pageIndex, cancellation: cancellation))
            guard detections.count <= 10_000 else { throw ConversionError.unsupported("Too many detected regions. Split this document before reviewing it.") }
            pages.append(SanitizePage(pngData: data, pointSize: size, pixelSize: CGSize(width: image.width, height: image.height)))
            totalPixels += image.width * image.height; totalBytes += data.count
        }
        if isPDF {
            let document = try PDFSafety.modifiableDocument(input)
            guard document.allowsPrinting, document.allowsCopying else { throw ConversionError.unsupported("This PDF does not permit rendering or text recognition.") }
            guard document.pageCount <= Self.maximumPages else { throw ConversionError.unsupported("Sanitize review supports up to 100 pages. Split this document first.") }
            for index in 0..<document.pageCount {
                try cancellation.check()
                try autoreleasepool {
                    guard let page = document.page(at: index) else { throw ConversionError.invalidInput("A PDF page could not be read.") }
                    try append(PDFDocumentTools.render(page, pixelLimit: 16_000_000), size: PDFDocumentTools.displayedSize(page))
                }
            }
        } else {
            guard FileKind.detect(input) == .image else { throw ConversionError.unsupported("Sanitize supports single-frame images and PDF documents.") }
            let image = try NativeConverter.decodedImage(input, maxDimension: 4096)
            try append(image, size: CGSize(width: image.width, height: image.height))
        }
        try Self.requireUnchanged(input, digest: originalDigest, cancellation: cancellation)
        return SanitizeDocument(input: input, sourceDigest: originalDigest, inputBytes: count, isPDF: isPDF, pages: pages, detections: detections)
    }

    public func sanitize(document: SanitizeDocument, regions: [RedactionRegion], style: SanitizeStyle,
                         outputDirectory: URL? = nil, cancellation: CancellationToken = CancellationToken()) throws -> ConversionResult {
        try cancellation.check()
        guard !document.pages.isEmpty, document.pages.count <= Self.maximumPages, regions.count <= 10_000 else { throw ConversionError.invalidInput("The review snapshot is invalid or too large.") }
        // Empty regions deliberately export a metadata-clean copy only after the user reviews it.
        for region in regions {
            let r = region.normalizedRect
            guard document.pages.indices.contains(region.pageIndex), [r.minX, r.minY, r.width, r.height].allSatisfy(\.isFinite),
                  r.width > 0, r.height > 0, r.minX >= 0, r.minY >= 0, r.maxX <= 1, r.maxY <= 1 else {
                throw ConversionError.invalidInput("A redaction region falls outside its displayed page.")
            }
        }
        try Self.requireUnchanged(document.input, digest: document.sourceDigest, cancellation: cancellation)
        let directory = try Self.outputDirectory(outputDirectory, input: document.input)
        let workspace = try Self.workspace(in: directory)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let output = workspace.appendingPathComponent(document.isPDF ? "sanitized.pdf" : "sanitized.png")
        let grouped = Dictionary(grouping: regions, by: \.pageIndex)
        if document.isPDF {
            let writer = try RasterPDFWriter(url: output, pageCount: document.pages.count)
            for index in document.pages.indices {
                try cancellation.check()
                try autoreleasepool {
                    let page = document.pages[index]
                    let image = try Self.replacementImage(page.pngData, regions: grouped[index]?.map(\.normalizedRect) ?? [], style: style)
                    try writer.append(image: image, size: page.pointSize, cancellation: cancellation)
                }
            }
            try writer.finish()
            guard let decoded = PDFDocument(url: output), decoded.pageCount == document.pages.count,
                  (decoded.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let pdf = CGPDFDocument(output as CFURL), pdf.info == nil else { throw ConversionError.failed("The sanitized PDF failed content-removal validation.") }
        } else {
            guard document.pages.count == 1 else { throw ConversionError.invalidInput("An image review must contain exactly one page.") }
            let image = try Self.replacementImage(document.pages[0].pngData, regions: grouped[0]?.map(\.normalizedRect) ?? [], style: style)
            try Self.encodeCleanPNG(image, to: output)
        }
        try Self.requireUnchanged(document.input, digest: document.sourceDigest, cancellation: cancellation)
        let note = regions.isEmpty
            ? "No regions were selected. Source metadata was removed, but visible personal information may remain."
            : "Selected pixels permanently replaced. Original metadata removed. \(document.isPDF ? "All PDF pages rasterized; searchable text, vectors, forms and attachments removed. " : "")Detection can miss information; review the output before sharing."
        return try Self.publish(output, input: document.input, inputBytes: document.inputBytes, directory: directory, note: note, cancellation: cancellation)
    }

    public nonisolated static func reviewRect(fromVision rectangle: CGRect, padding: CGFloat = 0.004) -> CGRect {
        let topLeft = CGRect(x: rectangle.minX, y: 1 - rectangle.maxY, width: rectangle.width, height: rectangle.height)
        return topLeft.insetBy(dx: -padding, dy: -padding).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    private static func recognize(_ image: CGImage, pageIndex: Int, cancellation: CancellationToken) throws -> [PrivacyDetection] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate; request.usesLanguageCorrection = false; request.automaticallyDetectsLanguage = true
        request.progressHandler = { request, _, _ in if cancellation.isCancelled { request.cancel() } }
        do { try VNImageRequestHandler(cgImage: image, options: [:]).perform([request]) }
        catch { try cancellation.check(); throw ConversionError.failed("Local text recognition failed: \(error.localizedDescription)") }
        try cancellation.check()
        var result: [PrivacyDetection] = []
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            for match in PIIDetector.matches(in: candidate.string) {
                guard let range = Range(match.range, in: candidate.string) else { continue }
                // If Vision cannot localize a token, include the whole line rather than omit a detected secret.
                let bounds = (try? candidate.boundingBox(for: range))?.boundingBox ?? observation.boundingBox
                let rectangle = reviewRect(fromVision: bounds)
                if !rectangle.isNull, rectangle.width > 0, rectangle.height > 0 {
                    result.append(PrivacyDetection(kind: match.kind, region: RedactionRegion(pageIndex: pageIndex, normalizedRect: rectangle)))
                }
            }
        }
        return result
    }

    private static func replacementImage(_ data: Data, regions: [CGRect], style: SanitizeStyle) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width > 0, image.height > 0, image.width <= 16_777_216 / image.height,
              let bitmap = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                     space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ConversionError.invalidInput("The review image cannot be decoded safely.")
        }
        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        bitmap.setShouldAntialias(false)
        for rect in regions {
            let x = floor(rect.minX * CGFloat(image.width)), right = ceil(rect.maxX * CGFloat(image.width))
            let y = floor((1 - rect.maxY) * CGFloat(image.height)), top = ceil((1 - rect.minY) * CGFloat(image.height))
            let area = CGRect(x: x, y: y, width: right - x, height: top - y)
            // Replace, never blur/sample. The opaque base irreversibly removes every selected pixel.
            bitmap.setBlendMode(.copy)
            bitmap.setFillColor(style == .obsidian ? CGColor(red: 0.025, green: 0.03, blue: 0.04, alpha: 1) : CGColor(red: 0.78, green: 0.87, blue: 0.88, alpha: 1))
            bitmap.fill(area)
            if style == .frosted {
                bitmap.saveGState(); bitmap.clip(to: area); bitmap.setBlendMode(.normal)
                let colors = [CGColor(red: 0.92, green: 0.97, blue: 0.98, alpha: 1), CGColor(red: 0.67, green: 0.79, blue: 0.81, alpha: 1)] as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1]) {
                    bitmap.drawLinearGradient(gradient, start: CGPoint(x: area.minX, y: area.maxY), end: CGPoint(x: area.maxX, y: area.minY), options: [])
                }
                bitmap.restoreGState()
            }
        }
        guard let result = bitmap.makeImage() else { throw ConversionError.failed("Could not render the redacted pixels.") }
        return result
    }
    private static func png(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { throw ConversionError.failed("Could not prepare the review image.") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ConversionError.failed("Could not encode the review image.") }
        return data as Data
    }
    /// ImageIO may synthesize a fresh eXIf block containing dimensions. Strip all metadata chunks,
    /// retaining only pixels/transparency and the color information required for faithful display.
    private static func encodeCleanPNG(_ image: CGImage, to output: URL) throws {
        let encoded = try png(image)
        let signature = Data([137, 80, 78, 71, 13, 10, 26, 10])
        guard encoded.starts(with: signature) else { throw ConversionError.failed("The image encoder produced an invalid PNG.") }
        let retained: Set<String> = ["IHDR", "PLTE", "IDAT", "IEND", "tRNS", "sRGB", "iCCP", "gAMA", "cHRM", "sBIT"]
        var cleaned = signature, offset = 8, ended = false
        while offset <= encoded.count - 12 {
            let size = encoded[offset..<(offset + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard UInt64(size) + 12 <= UInt64(encoded.count - offset),
                  let type = String(data: encoded[(offset + 4)..<(offset + 8)], encoding: .ascii) else {
                throw ConversionError.failed("The PNG encoder produced a malformed chunk.")
            }
            let end = offset + 12 + Int(size)
            if retained.contains(type) { cleaned.append(encoded[offset..<end]) }
            offset = end
            if type == "IEND" { ended = true; break }
        }
        guard ended, offset == encoded.count else { throw ConversionError.failed("The PNG encoder produced incomplete image data.") }
        try cleaned.write(to: output, options: .atomic)
        let check = try NativeConverter.decodedImage(output)
        guard check.width == image.width, check.height == image.height else { throw ConversionError.failed("The metadata-free image failed dimension validation.") }
    }
    private static func validateInput(_ input: URL) throws -> Int64 {
        guard input.isFileURL else { throw ConversionError.invalidInput("Choose a local image or PDF.") }
        let values = try input.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, let bytes = values.fileSize,
              bytes > 0, bytes <= 1_073_741_824 else { throw ConversionError.invalidInput("Choose a regular, nonempty image or PDF no larger than 1 GB.") }
        return Int64(bytes)
    }
    private static func digest(_ input: URL, cancellation: CancellationToken) throws -> Data {
        let file = try FileHandle(forReadingFrom: input); defer { try? file.close() }
        var hash = SHA256()
        while let chunk = try file.read(upToCount: 1_048_576), !chunk.isEmpty { try cancellation.check(); hash.update(data: chunk) }
        return Data(hash.finalize())
    }
    private static func requireUnchanged(_ input: URL, digest expected: Data, cancellation: CancellationToken) throws {
        _ = try validateInput(input)
        guard try digest(input, cancellation: cancellation) == expected else { throw ConversionError.invalidInput("The original changed after processing began. Reopen it and review the new content before exporting.") }
        try cancellation.check()
    }
    private static func outputDirectory(_ requested: URL?, input: URL) throws -> URL {
        let directory = (requested ?? input.deletingLastPathComponent()).standardizedFileURL
        guard directory.isFileURL, (try directory.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true else { throw ConversionError.invalidInput("Choose an existing local output folder.") }
        return directory
    }
    private static func workspace(in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(".fileorbit-neural-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return url
    }
    private static func publish(_ file: URL, input: URL, inputBytes: Int64, directory: URL, note: String, cancellation: CancellationToken) throws -> ConversionResult {
        let values = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize, size > 0 else { throw ConversionError.failed("The neural operation produced no usable output.") }
        try cancellation.check()
        let published = try OutputPublisher.publish(files: [file], source: input, directory: directory, compressed: false)
        return ConversionResult(outputURLs: published, inputBytes: inputBytes, outputBytes: Int64(size), note: note)
    }
}
