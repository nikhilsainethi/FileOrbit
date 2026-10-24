import Foundation
import CoreGraphics
import ImageIO

enum OutputEncoder {
    static func encode(_ image: CGImage, to output: URL, format: OutputFormat, environment: EngineEnvironment,
                       cancellation: CancellationToken) throws {
        try cancellation.check()
        guard format == .webp else { try NativeConverter.encode(image, to: output, format: format, quality: 0.92); return }
        guard let cwebp = environment.cwebpURL else { throw ConversionError.missingDependency("Install cwebp to enable local WebP encoding.") }
        guard image.width <= 16_383, image.height <= 16_383 else { throw ConversionError.unsupported("WebP images are limited to 16,383 pixels on either side. Choose another format for this image.") }
        let png = output.deletingLastPathComponent().appendingPathComponent("webp-source-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: png) }
        try NativeConverter.encode(image, to: png, format: .png, quality: 1)
        _ = try LocalProcess.run(executable: cwebp, arguments: ["-quiet", "-q", "92", "-metadata", "none", png.path, "-o", output.path], cancellation: cancellation, directory: output.deletingLastPathComponent())
        let handle = try FileHandle(forReadingFrom: output); defer { try? handle.close() }
        let prefix = try handle.read(upToCount: 12) ?? Data()
        guard prefix.count == 12, String(data: prefix.prefix(4), encoding: .ascii) == "RIFF",
              String(data: prefix[8..<12], encoding: .ascii) == "WEBP",
              let source = CGImageSourceCreateWithURL(output as CFURL, nil), CGImageSourceGetCount(source) == 1,
              let check = CGImageSourceCreateImageAtIndex(source, 0, nil), check.width == image.width, check.height == image.height else {
            throw ConversionError.failed("The WebP encoder produced an invalid image. No output was saved.")
        }
    }
}
