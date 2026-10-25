import Testing
import Foundation
@testable import FileOrbitCore

@Suite struct NeuralPrivacyTests {
    @Test func detectsBoundedTokensWithoutKeepingSecretsInLabels() {
        let text = "Contact alice@example.com or +1 (415) 555-0123. Card 4111 1111 1111 1111. Host 192.168.1.20 and 2001:db8::1; token ghp_abcdefghijklmnopqrstuvwxyz1234567890."
        let matches = PIIDetector.matches(in: text)
        for kind in [PrivacyKind.email, .phone, .card, .ipAddress, .apiKey] { #expect(matches.contains { $0.kind == kind }) }
        let emails = matches.filter { $0.kind == .email }
        #expect(emails.count == 1)
        #expect((text as NSString).substring(with: emails[0].range) == "alice@example.com")
        #expect(matches.allSatisfy { !$0.kind.title.contains("alice") })
    }
    @Test func validatesCardAndIPRatherThanMatchingArbitraryNumbers() {
        let matches = PIIDetector.matches(in: "Version 999.999.999.999 invalid card 4111 1111 1111 1112 and 0000 0000 0000 0000")
        #expect(!matches.contains { $0.kind == .card || $0.kind == .ipAddress })
    }
    @Test func addressRequiresStreetEvidenceNotJustLocation() {
        let matches = PIIDetector.matches(in: "Ship to 123 Main Street, Boston, MA 02110. Paris is lovely.")
        #expect(matches.contains { $0.kind == .address })
        #expect(!matches.contains { ("Ship to 123 Main Street, Boston, MA 02110. Paris is lovely." as NSString).substring(with: $0.range) == "Paris" })
    }
    @Test func compactPhonesAndFullSingleLinePostalAddressesAreIncluded() {
        let text = "Phone +442071838750 or 4155550123. Ship to 123 Main Street, Boston, MA 02110."
        let matches = PIIDetector.matches(in: text)
        for phone in ["+442071838750", "4155550123"] {
            #expect(matches.contains { $0.kind == .phone && (text as NSString).substring(with: $0.range) == phone })
        }
        #expect(matches.contains { $0.kind == .address && (text as NSString).substring(with: $0.range).contains("02110") })
    }
    @Test func visionCoordinatesBecomeClampedTopLeftRegions() {
        let rect = NeuralProcessingActor.reviewRect(fromVision: CGRect(x: 0.1, y: 0.6, width: 0.4, height: 0.2), padding: 0)
        #expect(abs(rect.minY - 0.2) < 0.00001)
        #expect(abs(rect.maxY - 0.4) < 0.00001)
        let edge = NeuralProcessingActor.reviewRect(fromVision: CGRect(x: 0, y: 0.9, width: 0.1, height: 0.1), padding: 0.01)
        #expect(edge.minX == 0 && edge.minY == 0 && edge.maxX <= 1 && edge.maxY <= 1)
    }
}

import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers
import PDFKit
import CryptoKit

@Suite(.serialized) struct NeuralOutputTests {
    func fixture() throws -> (URL, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("fileorbit-neural-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("privacy.png")
        let context = try #require(CGContext(data: nil, width: 1200, height: 400, bitsPerComponent: 8, bytesPerRow: 4800,
                                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 1200, height: 400))
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "alice@example.com", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 52, nil)]))
        context.textPosition = CGPoint(x: 100, y: 200); CTLineDraw(line, context)
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "PRIVATE METADATA"]] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return (folder, url)
    }
    @Test func actualOCRFindsEmailAndBothStylesRebuildImageWithoutMetadata() async throws {
        let (folder, url) = try fixture(); defer { try? FileManager.default.removeItem(at: folder) }
        let original = try Data(contentsOf: url)
        let actor = NeuralProcessingActor()
        let document = try await actor.inspect(input: url)
        #expect(document.pages.count == 1)
        #expect(document.detections.contains { $0.kind == .email })
        for style in SanitizeStyle.allCases {
            let result = try await actor.sanitize(document: document, regions: document.detections.map(\.region), style: style)
            let source = try #require(CGImageSourceCreateWithURL(result.outputURLs[0] as CFURL, nil))
            let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
            #expect(props[kCGImagePropertyExifDictionary as String] == nil)
            let rescanned = try await actor.inspect(input: result.outputURLs[0])
            #expect(!rescanned.detections.contains { $0.kind == .email })
            #expect(result.outputBytes == Int64(try Data(contentsOf: result.outputURLs[0]).count))
        }
        #expect(try Data(contentsOf: url) == original)
    }
    @Test func changedSourceAndInvalidRegionsAreRejectedBeforePublication() async throws {
        let (folder, url) = try fixture(); defer { try? FileManager.default.removeItem(at: folder) }
        let actor = NeuralProcessingActor(), document = try await actor.inspect(input: url)
        await #expect(throws: (any Error).self) { try await actor.sanitize(document: document, regions: [.init(pageIndex: 0, normalizedRect: CGRect(x: -0.1, y: 0, width: 1, height: 1))], style: .obsidian) }
        try Data("changed".utf8).write(to: url)
        await #expect(throws: (any Error).self) { try await actor.sanitize(document: document, regions: document.detections.map(\.region), style: .obsidian) }
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(names == ["privacy.png"])
    }
    @Test func cancellationDoesNotProduceOutput() async throws {
        let (folder, url) = try fixture(); defer { try? FileManager.default.removeItem(at: folder) }
        let token = CancellationToken(); token.cancel()
        await #expect(throws: (any Error).self) { try await NeuralProcessingActor().liftSubject(input: url, output: .transparentPNG, cancellation: token) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["privacy.png"])
    }
}

@Suite(.serialized) struct NeuralRedactionIntegrityTests {
    @Test func frostedReplacementDoesNotDependOnCoveredSecretPixels() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("fileorbit-neural-frost-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var results: [Data] = []
        for shade in [CGFloat(0), CGFloat(1)] {
            let input = folder.appendingPathComponent("source-\(Int(shade)).png")
            let context = try #require(CGContext(data: nil, width: 100, height: 80, bitsPerComponent: 8, bytesPerRow: 400, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(gray: shade, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 100, height: 80))
            try NativeConverter.encode(#require(context.makeImage()), to: input, format: .png, quality: 1)
            let data = try Data(contentsOf: input)
            let snapshot = SanitizeDocument(input: input, sourceDigest: Data(SHA256.hash(data: data)), inputBytes: Int64(data.count), isPDF: false,
                                            pages: [SanitizePage(pngData: data, pointSize: CGSize(width: 100, height: 80), pixelSize: CGSize(width: 100, height: 80))], detections: [])
            let output = try await NeuralProcessingActor().sanitize(document: snapshot, regions: [.init(pageIndex: 0, normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 1))], style: .frosted)
            results.append(try Data(contentsOf: output.outputURLs[0]))
        }
        #expect(results[0] == results[1])
    }
    @Test func everyPDFPageIsRebuiltWithoutUnderlyingTextOrInfo() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("fileorbit-neural-pdf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("source.pdf")
        var box = CGRect(x: 0, y: 0, width: 600, height: 220)
        let context = try #require(CGContext(input as CFURL, mediaBox: &box, [kCGPDFContextAuthor: "PRIVATE AUTHOR"] as CFDictionary))
        for index in 0..<2 {
            context.beginPDFPage(nil); context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(box)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: index == 0 ? "alice@example.com" : "SECOND PAGE VISIBLE TEXT", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 30, nil)]))
            context.textPosition = CGPoint(x: 30, y: 100); CTLineDraw(line, context); context.endPDFPage()
        }
        context.closePDF()
        let original = try Data(contentsOf: input), actor = NeuralProcessingActor()
        let document = try await actor.inspect(input: input)
        #expect(document.pages.count == 2)
        #expect(document.detections.contains { $0.kind == .email && $0.region.pageIndex == 0 })
        let result = try await actor.sanitize(document: document, regions: document.detections.map(\.region), style: .obsidian)
        let pdf = try #require(PDFDocument(url: result.outputURLs[0]))
        #expect(pdf.pageCount == 2)
        #expect((pdf.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        let raw = try #require(CGPDFDocument(result.outputURLs[0] as CFURL))
        #expect(raw.info == nil)
        let bytes = try Data(contentsOf: result.outputURLs[0])
        #expect(bytes.range(of: Data("PRIVATE AUTHOR".utf8)) == nil)
        #expect(bytes.range(of: Data("SECOND PAGE VISIBLE TEXT".utf8)) == nil)
        #expect(try Data(contentsOf: input) == original)
    }
}

@Suite struct NeuralSubjectTests {
    @Test func liveForegroundMaskProducesTransparentAndWhiteOutputs() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("fileorbit-neural-subject-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("studio-mug.png")
        let c = try #require(CGContext(data: nil, width: 640, height: 640, bitsPerComponent: 8, bytesPerRow: 2560,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        c.setFillColor(CGColor(red: 0.94, green: 0.92, blue: 0.88, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: 640, height: 640))
        c.setFillColor(CGColor(gray: 0.5, alpha: 0.2)); c.fillEllipse(in: CGRect(x: 125, y: 100, width: 410, height: 65))
        c.setStrokeColor(CGColor(red: 0.08, green: 0.27, blue: 0.45, alpha: 1)); c.setLineWidth(40)
        c.strokeEllipse(in: CGRect(x: 365, y: 205, width: 130, height: 180))
        c.saveGState()
        c.addPath(CGPath(roundedRect: CGRect(x: 165, y: 130, width: 255, height: 300), cornerWidth: 45, cornerHeight: 45, transform: nil)); c.clip()
        let gradient = try #require(CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [CGColor(red: 0.17, green: 0.52, blue: 0.73, alpha: 1), CGColor(red: 0.03, green: 0.18, blue: 0.32, alpha: 1)] as CFArray, locations: [0, 1]))
        c.drawLinearGradient(gradient, start: CGPoint(x: 165, y: 350), end: CGPoint(x: 420, y: 250), options: [])
        c.restoreGState()
        c.setFillColor(CGColor(red: 0.15, green: 0.4, blue: 0.58, alpha: 1)); c.fillEllipse(in: CGRect(x: 165, y: 397, width: 255, height: 65))
        c.setFillColor(CGColor(red: 0.05, green: 0.10, blue: 0.13, alpha: 1)); c.fillEllipse(in: CGRect(x: 180, y: 410, width: 225, height: 42))
        try NativeConverter.encode(#require(c.makeImage()), to: input, format: .png, quality: 1)
        let before = try Data(contentsOf: input), actor = NeuralProcessingActor()
        for output in SubjectOutput.allCases {
            let result = try await actor.liftSubject(input: input, output: output)
            let image = try NativeConverter.decodedImage(result.outputURLs[0])
            let bitmap = try #require(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                               bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            bitmap.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let bytes = try #require(bitmap.data?.assumingMemoryBound(to: UInt8.self))
            let alphas = stride(from: 3, to: image.width * image.height * 4, by: 4).map { bytes[$0] }
            if output == .transparentPNG { #expect(alphas.contains(0)); #expect(alphas.contains { $0 > 240 }) }
            else { #expect(alphas.allSatisfy { $0 == 255 }); #expect(bytes[0] > 250 && bytes[1] > 250 && bytes[2] > 250) }
        }
        #expect(try Data(contentsOf: input) == before)
    }
}
