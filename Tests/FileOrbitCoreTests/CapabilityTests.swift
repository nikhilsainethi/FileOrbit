import Testing
import Foundation
import ImageIO
import CoreGraphics
@testable import FileOrbitCore

struct CapabilityTests {
    private let empty = EngineEnvironment()
    private let full = EngineEnvironment(libreOfficeURL: URL(fileURLWithPath: "/usr/bin/true"), qpdfURL: URL(fileURLWithPath: "/usr/bin/true"), resvgURL: URL(fileURLWithPath: "/usr/bin/true"))
    private func file(_ name: String) -> URL { URL(fileURLWithPath: "/tmp/" + name) }

    @Test func testKnownFileFamiliesAndCaseInsensitiveExtensions() {
        #expect(FileKind.detect(file("a.PDF")) == .pdf)
        #expect(FileKind.detect(file("a.DOCX")) == .docx)
        #expect(FileKind.detect(file("a.pptx")) == .pptx)
        #expect(FileKind.detect(file("a.txt")) == .text)
        #expect(FileKind.detect(file("a.svg")) == .svg)
        #expect(FileKind.detect(file("a.png")) == .image)
        #expect(FileKind.detect(file("a.jpeg")) == .image)
        #expect(FileKind.detect(file("a.heic")) == .image)
        #expect(FileKind.detect(file("a.zip")) == .unsupported)
        #expect(FileKind.detect(file("a.exe")) == .unsupported)
    }

    @Test func testPNGExcludesSameFormatAndIncludesPDFAndCompression() {
        let actions = CapabilityCatalog.actions(for: file("a.png"), environment: empty)
        #expect(!(actions.contains { $0.operation == .convert(.png) }))
        #expect(actions.contains { $0.operation == .convert(.jpg) })
        #expect(actions.contains { $0.operation == .convert(.pdf) })
        #expect(actions.contains { $0.operation == .compress(.balanced) })
    }

    @Test func testImageActionsOnlyUseAvailableEncoders() {
        let actions = CapabilityCatalog.actions(for: file("a.png"), environment: empty)
        for action in actions {
            if case .convert(let format) = action.operation, format != .pdf {
                #expect(CapabilityCatalog.nativeOutputFormats.contains(format))
            }
        }
    }

    @Test func testPDFCompressionRequiresQPDFButExportsDoNot() {
        let without = CapabilityCatalog.actions(for: file("a.pdf"), environment: empty)
        #expect(without.map(\.operation) == [.convert(.png), .convert(.jpg), .convert(.txt)])
        #expect(CapabilityCatalog.actions(for: file("a.pdf"), environment: full).contains { $0.operation == .compress(.balanced) })
        #expect(CapabilityCatalog.unavailableReason(for: file("a.pdf"), environment: empty) != nil)
    }

    @Test func testDOCXCompressionDoesNotRequireLibreOffice() {
        #expect(CapabilityCatalog.actions(for: file("a.docx"), environment: empty).map(\.operation) == [.compress(.balanced)])
        #expect(CapabilityCatalog.actions(for: file("a.docx"), environment: full).map(\.operation) == [.convert(.pdf), .convert(.txt), .compress(.balanced)])
    }

    @Test func testOfficeAndSVGActionsRequireTheirActualEngines() {
        for name in ["a.pptx", "a.txt", "a.svg"] {
            #expect(CapabilityCatalog.actions(for: file(name), environment: empty).isEmpty)
            #expect(CapabilityCatalog.unavailableReason(for: file(name), environment: empty) != nil)
            #expect(!(CapabilityCatalog.actions(for: file(name), environment: full).isEmpty))
        }
        #expect(CapabilityCatalog.actions(for: file("a.pptx"), environment: full).map(\.operation) == [.convert(.pdf), .convert(.png), .convert(.jpg)])
        #expect(CapabilityCatalog.actions(for: file("a.txt"), environment: full).map(\.operation) == [.convert(.pdf), .convert(.docx)])
        #expect(CapabilityCatalog.actions(for: file("a.svg"), environment: full).map(\.operation) == [.convert(.png), .convert(.jpg)])
    }

    @Test func testUnsupportedInputNeverOffersActions() {
        #expect(CapabilityCatalog.actions(for: file("archive.zip"), environment: full).isEmpty)
        #expect(CapabilityCatalog.unavailableReason(for: file("archive.zip"), environment: full) != nil)
    }

    @Test func testOverridesRequireExecutableRegularFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let tool = folder.appendingPathComponent("tool with spaces")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: tool)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        let env = EngineEnvironment.discover(environment: ["FILEORBIT_SOFFICE": tool.path, "FILEORBIT_QPDF": folder.path, "FILEORBIT_RESVG": tool.path])
        #expect(env.libreOfficeURL == tool)
        #expect(env.resvgURL == tool)
        #expect(env.qpdfURL != folder)
    }

    @Test func testPreferenceAndBundledHelperResolutionWithOverridePrecedence() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let bundle = folder.appendingPathComponent("FileOrbit.app")
        let bundledQPDF = bundle.appendingPathComponent("Contents/Helpers/qpdf/bin/qpdf")
        let bundledResvg = bundle.appendingPathComponent("Contents/Helpers/resvg")
        let preferred = folder.appendingPathComponent("preferred")
        let override = folder.appendingPathComponent("override")
        for tool in [bundledQPDF, bundledResvg, preferred, override] {
            try FileManager.default.createDirectory(at: tool.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: tool)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        }
        // Explicit environment variables take priority over user preferences.
        let env = EngineEnvironment.discover(environment: ["FILEORBIT_QPDF": override.path], preferences: ["FileOrbit.qpdfPath": preferred.path, "FileOrbit.libreOfficePath": preferred.path], bundleURL: bundle)
        #expect(env.qpdfURL == override)
        #expect(env.libreOfficeURL == preferred)
        #expect(env.resvgURL == bundledResvg)
        let bundled = EngineEnvironment.discover(environment: [:], preferences: [:], bundleURL: bundle)
        #expect(bundled.qpdfURL == bundledQPDF)
        let preferences = EngineEnvironment.discover(environment: [:], preferences: ["FileOrbit.qpdfPath": preferred.path], bundleURL: bundle)
        #expect(preferences.qpdfURL == preferred)
    }

    @Test func testMultiPageImageDoesNotOfferSingleFrameActions() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".tiff")
        defer { try? FileManager.default.removeItem(at: url) }
        let context = try #require(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(context.makeImage())
        let output = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.tiff" as CFString, 2, nil))
        CGImageDestinationAddImage(output, image, nil)
        CGImageDestinationAddImage(output, image, nil)
        #expect(CGImageDestinationFinalize(output))
        #expect(CapabilityCatalog.actions(for: url, environment: full).isEmpty)
        #expect(CapabilityCatalog.unavailableReason(for: url, environment: full)?.contains("multi-page") == true)
    }

    @Test func testDirectoriesAndNonFileURLsAreUnsupported() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(FileKind.detect(folder) == .unsupported)
        #expect(FileKind.detect(try #require(URL(string: "https://example.com/a.pdf"))) == .unsupported)
    }
}
