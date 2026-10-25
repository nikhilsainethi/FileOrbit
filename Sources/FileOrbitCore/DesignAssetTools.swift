import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

public struct PaletteColor: Sendable, Equatable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8
    public var hex: String { String(format: "#%02X%02X%02X", red, green, blue) }
    public var swiftUI: String { String(format: "Color(red: %.6f, green: %.6f, blue: %.6f)", Double(red) / 255, Double(green) / 255, Double(blue) / 255) }
}

enum DesignAssetTools {
    static func iconset(input: URL, workspace: URL, cancellation: CancellationToken) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width == height, width >= 1024 else {
            throw ConversionError.unsupported("A macOS AppIconset needs a square source at least 1024 × 1024 pixels. No aspect-ratio changes or upscaling were applied.")
        }
        let image = try NativeConverter.decodedImage(input, maxDimension: 1024)
        guard image.width == image.height, image.width >= 1024 else {
            throw ConversionError.unsupported("A macOS AppIconset needs a square source at least 1024 × 1024 pixels. Resize or crop the source before generating icons.")
        }
        let directory = workspace.appendingPathComponent("AppIcon.appiconset", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        var slots: [[String: String]] = []
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                try cancellation.check()
                let pixels = size * scale, name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
                guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: pixels * 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                    throw ConversionError.failed("Could not allocate an icon rendition.")
                }
                context.interpolationQuality = .high
                context.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
                guard let resized = context.makeImage() else { throw ConversionError.failed("Could not render an icon rendition.") }
                try NativeConverter.encode(resized, to: directory.appendingPathComponent(name), format: .png, quality: 1)
                slots.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": name])
            }
        }
        let manifest: [String: Any] = ["images": slots, "info": ["version": 1, "author": "FileOrbit"]]
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys, .prettyPrinted]).write(to: directory.appendingPathComponent("Contents.json"))
        return directory
    }
    static func dominantColors(input: URL, cancellation: CancellationToken) throws -> [PaletteColor] {
        let image = try NativeConverter.decodedImage(input, maxDimension: 256)
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
            throw ConversionError.failed("Could not sample the image colors.")
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { throw ConversionError.failed("Could not read the color sample.") }
        struct Bucket { var weight: Int = 0; var red: Int64 = 0; var green: Int64 = 0; var blue: Int64 = 0 }
        var buckets: [Int: Bucket] = [:]
        for index in 0..<(image.width * image.height) {
            if index % 2048 == 0 { try cancellation.check() }
            let offset = index * 4, alpha = Int(pixels[offset + 3]); guard alpha >= 32 else { continue }
            let red = min(255, Int(pixels[offset]) * 255 / alpha), green = min(255, Int(pixels[offset + 1]) * 255 / alpha), blue = min(255, Int(pixels[offset + 2]) * 255 / alpha)
            let key = ((red >> 3) << 10) | ((green >> 3) << 5) | (blue >> 3)
            var bucket = buckets[key] ?? Bucket(); bucket.weight += alpha
            bucket.red += Int64(red * alpha); bucket.green += Int64(green * alpha); bucket.blue += Int64(blue * alpha); buckets[key] = bucket
        }
        let ordered = buckets.keys.sorted { left, right in
            if buckets[left]!.weight == buckets[right]!.weight { return left < right }
            return buckets[left]!.weight > buckets[right]!.weight
        }
        var result: [PaletteColor] = []
        for key in ordered {
            let bucket = buckets[key]!, weight = Int64(bucket.weight)
            let color = PaletteColor(red: UInt8(bucket.red / weight), green: UInt8(bucket.green / weight), blue: UInt8(bucket.blue / weight))
            let distinct = result.allSatisfy { other in
                let r = Int(other.red) - Int(color.red), g = Int(other.green) - Int(color.green), b = Int(other.blue) - Int(color.blue)
                return r * r + g * g + b * b >= 1600
            }
            if distinct { result.append(color) }
            if result.count == 5 { break }
        }
        guard !result.isEmpty else { throw ConversionError.unsupported("This image contains no sufficiently opaque colors to sample.") }
        return result
    }
    static func palette(input: URL, workspace: URL, cancellation: CancellationToken) throws -> [URL] {
        let colors = try dominantColors(input: input, cancellation: cancellation)
        let width = 1200, height = 540
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw ConversionError.failed("Could not create the palette card.")
        }
        context.setFillColor(CGColor(red: 0.07, green: 0.08, blue: 0.11, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        func label(_ string: String, x: CGFloat, y: CGFloat, size: CGFloat, color: CGColor) {
            let font = CTFontCreateWithName("HelveticaNeue-Medium" as CFString, size, nil)
            let attributed = NSAttributedString(string: string, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): color])
            context.textPosition = CGPoint(x: x, y: y); CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        }
        label("FILEORBIT  /  DOMINANT COLORS", x: 54, y: 470, size: 25, color: CGColor(gray: 0.95, alpha: 1))
        let spacing = 18.0, available = Double(width) - 108, swatchWidth = (available - Double(colors.count - 1) * spacing) / Double(colors.count)
        for (index, color) in colors.enumerated() {
            let x = 54 + Double(index) * (swatchWidth + spacing)
            context.setFillColor(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [Double(color.red) / 255, Double(color.green) / 255, Double(color.blue) / 255, 1])!)
            context.addPath(CGPath(roundedRect: CGRect(x: x, y: 148, width: swatchWidth, height: 274), cornerWidth: 18, cornerHeight: 18, transform: nil)); context.fillPath()
            label(color.hex, x: x + 8, y: 100, size: 26, color: CGColor(gray: 0.98, alpha: 1))
        }
        label("SAMPLED LOCALLY · sRGB · TRANSPARENCY WEIGHTED", x: 54, y: 42, size: 15, color: CGColor(gray: 0.65, alpha: 1))
        guard let image = context.makeImage() else { throw ConversionError.failed("Could not render the palette card.") }
        let png = workspace.appendingPathComponent("Color Palette.png"), text = workspace.appendingPathComponent("Color Palette.txt")
        try NativeConverter.encode(image, to: png, format: .png, quality: 1)
        let snippets = "// FileOrbit dominant palette. Approximate sRGB colors sampled from oriented image pixels.\nimport SwiftUI\n\n" + colors.enumerated().map { "// \($0.element.hex)\nlet color\($0.offset + 1) = \($0.element.swiftUI)" }.joined(separator: "\n\n") + "\n"
        try Data(snippets.utf8).write(to: text)
        return [png, text]
    }
}
