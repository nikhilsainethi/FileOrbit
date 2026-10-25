import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
import CryptoKit

public struct ImagePreviewResult: Sendable {
    public let originalCropPNG: Data
    public let outputCropPNG: Data
    public let encodedOutput: Data
    public let inputBytes: Int
    public var outputBytes: Int { encodedOutput.count }
    public let width: Int
    public let height: Int
    public let ssim: Double
    public let comparisonNote: String
}

/// One bounded encoding at a time. Results never publish files or change the clipboard.
public actor ImagePreviewActor {
    public init() {}
    public func preview(input: URL, operation: FileOperation, environment: EngineEnvironment,
                        cancellation: CancellationToken = CancellationToken()) throws -> ImagePreviewResult {
        try cancellation.check()
        let values = try input.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard input.isFileURL, values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= 128_000_000 else {
            throw ConversionError.unsupported("Live preview supports regular images up to 128 MB.")
        }
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil), CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0, width <= 32_000_000 / height else {
            throw ConversionError.unsupported("Live preview supports single-frame images up to 32 megapixels.")
        }
        let digest = SHA256.hash(data: try Data(contentsOf: input, options: .mappedIfSafe))
        let format: OutputFormat, quality: Double, maximum: Int?
        switch operation {
        case .convert(let target) where [.png, .jpg, .heic, .tiff, .webp].contains(target):
            format = target; quality = 0.92; maximum = nil
        case .compress(let preset):
            switch CGImageSourceGetType(source) as String? {
            case UTType.jpeg.identifier: format = .jpg
            case UTType.png.identifier: format = .png
            case UTType.heic.identifier, UTType.heif.identifier: format = .heic
            case UTType.tiff.identifier: format = .tiff
            default: throw ConversionError.unsupported("This image has no compression preview.")
            }
            switch preset { case .gentle: maximum = 4096; quality = 0.9; case .balanced: maximum = 2560; quality = 0.78; case .small: maximum = 1600; quality = 0.6 }
        default: throw ConversionError.unsupported("Hold Space over an image conversion or compression action.")
        }
        let original = try NativeConverter.decodedImage(input)
        let prepared = maximum == nil ? original : try NativeConverter.decodedImage(input, maxDimension: maximum)
        try cancellation.check()
        let data: Data
        if format == .webp {
            let workspace = FileManager.default.temporaryDirectory.appendingPathComponent("fileorbit-loupe-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: workspace) }
            let output = workspace.appendingPathComponent("preview.webp")
            try OutputEncoder.encode(prepared, to: output, format: format, environment: environment, cancellation: cancellation)
            data = try Data(contentsOf: output)
        } else { data = try NativeConverter.encodedData(prepared, format: format, quality: quality) }
        try cancellation.check()
        guard let encodedSource = CGImageSourceCreateWithData(data as CFData, nil), let decoded = CGImageSourceCreateImageAtIndex(encodedSource, 0, nil) else {
            throw ConversionError.failed("Could not decode the encoded preview.")
        }
        let comparisonWidth = min(1024, decoded.width)
        let comparisonHeight = max(1, Int(Double(decoded.height) * Double(comparisonWidth) / Double(decoded.width)))
        // Panoramic/portrait images must also respect the comparison sample budget.
        let factor = min(1.0, 1024.0 / Double(comparisonHeight))
        let cw = max(1, Int(Double(comparisonWidth) * factor)), ch = max(1, Int(Double(comparisonHeight) * factor))
        let a = try Self.luma(original, width: cw, height: ch), b = try Self.luma(decoded, width: cw, height: ch)
        let ssim = try StructuralSimilarity.measure(a, b, width: cw, height: ch)
        let sourceCrop = try Self.centerCrop(original, regionFraction: 130.0 / Double(decoded.width))
        let outputCrop = try Self.centerCrop(decoded, regionFraction: 130.0 / Double(decoded.width))
        try cancellation.check()
        guard SHA256.hash(data: try Data(contentsOf: input, options: .mappedIfSafe)) == digest else {
            throw ConversionError.invalidInput("The source changed during preview. Hold Space again to refresh it.")
        }
        let resized = original.width != decoded.width || original.height != decoded.height
        return ImagePreviewResult(originalCropPNG: try NativeConverter.encodedData(sourceCrop, format: .png, quality: 1),
                                  outputCropPNG: try NativeConverter.encodedData(outputCrop, format: .png, quality: 1), encodedOutput: data,
                                  inputBytes: size, width: decoded.width, height: decoded.height, ssim: ssim,
                                  comparisonNote: "200% center crop · SSIM sampled across the full image (\(cw)×\(ch), sRGB luma" + (resized ? "; source aligned to output size)." : ")."))
    }
    private static func centerCrop(_ image: CGImage, regionFraction: Double) throws -> CGImage {
        // Always render a 130-pixel crop into 260 points. Small images are centered
        // with transparent padding rather than falsely magnified beyond 200%.
        let requestedSide = max(1, Double(image.width) * regionFraction)
        let scale = 130.0 / requestedSide
        guard let context = CGContext(data: nil, width: 130, height: 130, bitsPerComponent: 8, bytesPerRow: 520,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ConversionError.failed("Could not allocate the loupe crop.")
        }
        context.interpolationQuality = .high
        let width = Double(image.width) * scale, height = Double(image.height) * scale
        context.draw(image, in: CGRect(x: (130 - width) / 2, y: (130 - height) / 2, width: width, height: height))
        guard let crop = context.makeImage() else { throw ConversionError.failed("Could not crop the preview.") }
        return crop
    }
    private static func luma(_ image: CGImage, width: Int, height: Int) throws -> [Double] {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
            throw ConversionError.failed("Could not allocate the comparison buffer.")
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high; context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let pointer = context.data?.assumingMemoryBound(to: UInt8.self) else { throw ConversionError.failed("Comparison pixels unavailable.") }
        return (0..<(width * height)).map { index in
            let p = pointer + index * 4
            return (0.2126 * Double(p[0]) + 0.7152 * Double(p[1]) + 0.0722 * Double(p[2])) / 255
        }
    }
}
