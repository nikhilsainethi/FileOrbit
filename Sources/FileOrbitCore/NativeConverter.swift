import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics
import PDFKit

/// Raster and PDF adapters. Every returned URL belongs to the caller's private workspace.
enum NativeConverter {
    static let maximumImagePixels = 100_000_000
    static let maximumPDFPages = 1_000

    static func convert(input: URL, to format: OutputFormat, workspace: URL, cancellation: CancellationToken, environment: EngineEnvironment = EngineEnvironment()) throws -> [URL] {
        try cancellation.check()
        let image = try decodedImage(input)
        let output = workspace.appendingPathComponent("image.\(format.rawValue)")
        if format == .pdf {
            // One point per pixel, bounded to a sensible maximum page size without changing aspect ratio.
            let scale = min(1.0, 14400.0 / Double(max(image.width, image.height)))
            var rect = CGRect(x: 0, y: 0, width: Double(image.width) * scale, height: Double(image.height) * scale)
            guard let context = CGContext(output as CFURL, mediaBox: &rect, nil) else {
                throw ConversionError.failed("Could not create the PDF output.")
            }
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(rect)
            context.draw(image, in: rect)
            context.endPDFPage()
            context.closePDF()
        } else {
            try OutputEncoder.encode(image, to: output, format: format, environment: environment, cancellation: cancellation)
        }
        try cancellation.check()
        return [output]
    }

    static func compress(input: URL, preset: CompressionPreset, workspace: URL, cancellation: CancellationToken) throws -> [URL] {
        try cancellation.check()
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil), let type = CGImageSourceGetType(source) else {
            throw ConversionError.invalidInput("This image could not be decoded.")
        }
        let format: OutputFormat
        switch type as String {
        case UTType.jpeg.identifier: format = .jpg
        case UTType.png.identifier: format = .png
        case UTType.heic.identifier, UTType.heif.identifier: format = .heic
        case UTType.tiff.identifier: format = .tiff
        default: throw ConversionError.unsupported("Compression currently supports JPEG, PNG, HEIC and TIFF images.")
        }
        let maxDimension: Int
        let quality: Double
        switch preset {
        case .gentle: maxDimension = 4096; quality = 0.9
        case .balanced: maxDimension = 2560; quality = 0.78
        case .small: maxDimension = 1600; quality = 0.6
        }
        let image = try decodedImage(input, maxDimension: maxDimension)
        let output = workspace.appendingPathComponent("compressed.\(format.rawValue)")
        try encode(image, to: output, format: format, quality: quality)
        try cancellation.check()
        return [output]
    }

    static func decodedImage(_ input: URL, maxDimension: Int? = nil) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw ConversionError.invalidInput("This file is not a readable image.")
        }
        guard CGImageSourceGetCount(source) == 1 else {
            throw ConversionError.unsupported("Animated and multipage images are not supported yet. No frames were discarded.")
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0, width <= maximumImagePixels / height else {
            throw ConversionError.invalidInput("This image is invalid or exceeds the 100-megapixel processing limit.")
        }
        let target = min(maxDimension ?? max(width, height), max(width, height))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: target,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ConversionError.invalidInput("The image data is damaged or could not be decoded.")
        }
        return image
    }

    static func encode(_ image: CGImage, to url: URL, format: OutputFormat, quality: Double) throws {
        let type: String
        switch format {
        case .jpg: type = UTType.jpeg.identifier
        case .png: type = UTType.png.identifier
        case .heic: type = UTType.heic.identifier
        case .tiff: type = UTType.tiff.identifier
        default: throw ConversionError.unsupported("This is not a supported image output format.")
        }
        guard (CGImageDestinationCopyTypeIdentifiers() as! [String]).contains(type) else {
            throw ConversionError.unsupported("This Mac cannot encode \(format.rawValue.uppercased()) images.")
        }
        let prepared = format == .jpg ? try whiteBackground(image) : image
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil) else {
            throw ConversionError.failed("Could not create the image output.")
        }
        var properties: [CFString: Any] = [kCGImagePropertyOrientation: 1]
        if format == .jpg || format == .heic { properties[kCGImageDestinationLossyCompressionQuality] = quality }
        if format == .tiff { properties[kCGImagePropertyTIFFDictionary] = [kCGImagePropertyTIFFCompression: 5] }
        CGImageDestinationAddImage(destination, prepared, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination),
              let check = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(check) == 1,
              let decoded = CGImageSourceCreateImageAtIndex(check, 0, nil),
              decoded.width == image.width, decoded.height == image.height else {
            throw ConversionError.failed("The encoded image failed validation. No output was saved.")
        }
    }

    static func whiteBackground(_ image: CGImage) throws -> CGImage {
        let space = image.colorSpace?.model == .rgb ? image.colorSpace! : CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: image.width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw ConversionError.failed("Could not prepare the image background.")
        }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        guard let flattened = context.makeImage() else { throw ConversionError.failed("Could not flatten image transparency.") }
        return flattened
    }

    static func readablePDF(_ input: URL) throws -> PDFDocument {
        guard let document = PDFDocument(url: input), document.pageCount > 0 else {
            throw ConversionError.invalidInput("This PDF is damaged, empty, or cannot be opened.")
        }
        guard !document.isEncrypted else {
            throw ConversionError.unsupported("Encrypted or password-protected PDFs are not supported in this release.")
        }
        guard document.pageCount <= maximumPDFPages else {
            throw ConversionError.unsupported("PDF processing is limited to 1,000 pages per file.")
        }
        return document
    }

    static func convertPDF(input: URL, to format: OutputFormat, workspace: URL, cancellation: CancellationToken) throws -> [URL] {
        try cancellation.check()
        let document = try readablePDF(input)
        if format == .txt {
            guard document.allowsCopying else { throw ConversionError.unsupported("This PDF does not allow text extraction.") }
            var pages: [String] = []
            for index in 0..<document.pageCount {
                try cancellation.check()
                pages.append(document.page(at: index)?.string ?? "")
            }
            let text = pages.joined(separator: "\n\u{000C}\n")
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)).isEmpty else {
                throw ConversionError.unsupported("This PDF has no extractable text layer. Use OCR to recognize text from scanned pages.")
            }
            let output = workspace.appendingPathComponent("text.txt")
            try text.write(to: output, atomically: true, encoding: .utf8)
            return [output]
        }
        return try PDFDocumentTools.export(input: input, format: format, mode: .allPages, workspace: workspace, cancellation: cancellation)
    }
}
