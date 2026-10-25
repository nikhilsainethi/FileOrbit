import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import FileOrbitCore

@Suite("Developer payload transformations")
struct DeveloperPayloadTests {
    func workspace() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("FileOrbit-payload-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func write(_ text: String, _ name: String, in folder: URL) throws -> URL {
        let url = folder.appendingPathComponent(name); try Data(text.utf8).write(to: url); return url
    }
    func convert(_ input: URL, _ format: StructuredFormat) throws -> URL {
        try DeveloperPayloadEngine().run(input: input, operation: .convertData(format)).outputURLs[0]
    }
    @Test func jsonYAMLRoundTripPreservesUnicodeTypesAndLargeNumbers() throws {
        let folder = try workspace(); defer { try? FileManager.default.removeItem(at: folder) }
        let original = #"{"name":"Café 日本語","enabled":true,"count":9007199254740993,"list":[1,null,"yes"],"nested":{"url":"https://example.org/a:b"}}"#
        let input = try write(original, "data.json", in: folder)
        let yaml = try convert(input, .yaml), json = try convert(yaml, .json)
        #expect(try String(contentsOf: json, encoding: .utf8).contains("9007199254740993"))
        #expect(try StructuredDocument.read(Data(contentsOf: input), format: .json) == StructuredDocument.read(Data(contentsOf: json), format: .json))
        #expect(try String(contentsOf: input, encoding: .utf8) == original)
    }
    @Test func blockYAMLParsesNestedRecordsWithoutChangingPlainStrings() throws {
        let folder = try workspace(); defer { try? FileManager.default.removeItem(at: folder) }
        let input = try write("people:\n  - name: 'Ada, Lovelace'\n    active: true\n    note: 2026-10-24\n  - name: Grace\n    active: false\n    note: 'yes'\n", "data.yaml", in: folder)
        let json = try String(contentsOf: convert(input, .json), encoding: .utf8)
        #expect(json.contains("Ada, Lovelace")); #expect(json.contains("2026-10-24")); #expect(json.contains("\"yes\""))
    }
    @Test(arguments: ["key: one\nkey: two", "value: &anchor 3", "value: *anchor", "value: !!python/object:x {}", "value: |\n  multiline", "a:\n\tb: 2"])
    func unsafeOrUnsupportedYAMLIsRejected(_ value: String) throws {
        #expect(throws: (any Error).self) { try StructuredDocument.read(Data(value.utf8), format: .yaml) }
    }
    @Test func YAMLSequenceAcceptsJSONFlowRecords() throws {
        let yaml = "- {\"name\": \"Ada\", \"tags\": [1, 2]}\n- {\"name\": \"Grace\", \"tags\": [3]}\n"
        let actual = try StructuredDocument.read(Data(yaml.utf8), format: .yaml)
        let expected = try StructuredDocument.read(Data(#"[{"name":"Ada","tags":[1,2]},{"name":"Grace","tags":[3]}]"#.utf8), format: .json)
        #expect(actual == expected)
    }
    @Test func JSONDuplicateKeysAndExcessiveNestingAreRejected() throws {
        #expect(throws: (any Error).self) { try StructuredDocument.read(Data(#"{"a":1,"a":2}"#.utf8), format: .json) }
        #expect(throws: (any Error).self) { try StructuredDocument.read(Data((String(repeating: "[", count: 70) + "0" + String(repeating: "]", count: 70)).utf8), format: .json) }
    }
    @Test func CSVQuotedNewlinesAndEmptyStringsRoundTrip() throws {
        let folder = try workspace(); defer { try? FileManager.default.removeItem(at: folder) }
        let csv = "name,note,empty\r\n\"Café, Inc.\",\"line 1\r\nline \"\"2\"\"\",\"\"\r\n"
        let input = try write(csv, "table.csv", in: folder)
        let json = try convert(input, .json), back = try convert(json, .csv)
        #expect(try StructuredDocument.read(Data(contentsOf: input), format: .csv) == StructuredDocument.read(Data(contentsOf: back), format: .csv))
    }
    @Test(arguments: ["a,a\n1,2", "a,b\n1", "a\n\"unterminated", "a\n\"one\"junk", "a\none\"two"])
    func malformedCSVIsRejected(_ csv: String) throws {
        #expect(throws: (any Error).self) { try StructuredDocument.read(Data(csv.utf8), format: .csv) }
    }
    @Test func nestedOrInconsistentObjectsCannotSilentlyBecomeCSV() throws {
        for json in [#"[{"a":{"b":1}}]"#, #"[{"a":1},{"b":2}]"#, #"[{"a":null}]"#] {
            let value = try StructuredDocument.read(Data(json.utf8), format: .json)
            #expect(throws: (any Error).self) { try StructuredDocument.write(value, format: .csv) }
        }
    }
    @Test func generatedSwiftHasSafeKeysAndExplicitSchemaTemplate() throws {
        let folder = try workspace(); defer { try? FileManager.default.removeItem(at: folder) }
        let input = try write(#"{"class":"yes","first-name":"Ada","count":3,"nested":{"ok":true},"people":[{"name":"One","age":2},{"name":"Two"}]}"#, "model.json", in: folder)
        let output = try convert(input, .swift)
        let code = try String(contentsOf: output, encoding: .utf8)
        #expect(code.contains("CodingKeys")); #expect(code.contains("first-name")); #expect(code.contains("Int?"))
        let swift = URL(fileURLWithPath: "/usr/bin/xcrun")
        _ = try LocalProcess.run(executable: swift, arguments: ["swiftc", "-typecheck", "-swift-version", "6", "-warnings-as-errors", output.path], cancellation: CancellationToken())
        let result = try DeveloperPayloadEngine().run(input: output, operation: .convertData(.json))
        #expect(result.note?.contains("template") == true)
        let template = try String(contentsOf: result.outputURLs[0], encoding: .utf8)
        #expect(template.contains("first-name")); #expect(!template.contains("Ada"))
    }
    @Test func generatedSwiftEscapesSlashControlCharactersAndUnicodeKeys() throws {
        let folder = try workspace(); defer { try? FileManager.default.removeItem(at: folder) }
        let node = StructuredValue.object(["a/b": .string("value"), "control\u{0001}": .bool(true), "日本語": .number("2"), "quote\"slash\\": .string("text")])
        let generated = try StructuredDocument.write(node, format: .swift)
        let output = folder.appendingPathComponent("Model.swift"); try generated.write(to: output)
        _ = try LocalProcess.run(executable: URL(fileURLWithPath: "/usr/bin/xcrun"), arguments: ["swiftc", "-typecheck", "-swift-version", "6", "-warnings-as-errors", output.path], cancellation: CancellationToken())
        guard case .object(let restored) = try StructuredDocument.read(generated, format: .swift) else { Issue.record("Expected schema object"); return }
        #expect(Set(restored.keys) == ["a/b", "control\u{0001}", "日本語", "quote\"slash\\"])
    }
    @Test func YAMLRejectsImplicitNonstringKeysAndUnsupportedInlineSequences() throws {
        for source in ["true: value", "123: value", "value: - nested", "value: 0123", "value: 0xFF", "value: +1", "value: 1_000"] {
            #expect(throws: (any Error).self) { try StructuredDocument.read(Data(source.utf8), format: .yaml) }
        }
    }
    @Test func generatedSwiftEscapesReservedIdentifiers() throws {
        let folder = try workspace(); defer { try? FileManager.default.removeItem(at: folder) }
        let keys = ["guard", "defer", "break", "continue", "fallthrough", "precedencegroup", "self", "Type"]
        let model = StructuredValue.object(Dictionary(uniqueKeysWithValues: keys.map { ($0, StructuredValue.string("fixture")) }))
        let source = folder.appendingPathComponent("Keywords.swift"); try StructuredDocument.write(model, format: .swift).write(to: source)
        _ = try LocalProcess.run(executable: URL(fileURLWithPath: "/usr/bin/xcrun"), arguments: ["swiftc", "-typecheck", "-swift-version", "6", "-warnings-as-errors", source.path], cancellation: CancellationToken())
    }
    @Test func heterogeneousSwiftSchemaRejectsGuessing() throws {
        let node = try StructuredDocument.read(Data(#"{"value":[1,"two"]}"#.utf8), format: .json)
        #expect(throws: (any Error).self) { try StructuredDocument.write(node, format: .swift) }
        #expect(throws: (any Error).self) { try StructuredDocument.read(Data("import Foundation\nprint(\"execute\")".utf8), format: .swift) }
    }
    @Test func cancellationAndErrorsLeaveNoArtifacts() throws {
        let folder = try workspace(); defer { try? FileManager.default.removeItem(at: folder) }
        let input = try write("{broken", "broken.json", in: folder)
        #expect(throws: (any Error).self) { try convert(input, .yaml) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["broken.json"])
        let token = CancellationToken(); token.cancel()
        #expect(throws: (any Error).self) { try DeveloperPayloadEngine().run(input: input, operation: .convertData(.yaml), cancellation: token) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["broken.json"])
    }
    func image(in folder: URL, size: Int = 1024) throws -> URL {
        let context = try #require(CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [1, 0, 0, 1])!); context.fill(CGRect(x: 0, y: 0, width: size / 2, height: size))
        context.setFillColor(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [0, 0, 1, 1])!); context.fill(CGRect(x: size / 2, y: 0, width: size / 2, height: size))
        let url = folder.appendingPathComponent("icon.png")
        try NativeConverter.encode(#require(context.makeImage()), to: url, format: .png, quality: 1)
        return url
    }
    @Test func appIconsetHasValidMacSlotsAndNeverOverwrites() throws {
        let folder = try workspace(); defer { try? FileManager.default.removeItem(at: folder) }
        let input = try image(in: folder), before = try Data(contentsOf: input)
        let engine = DeveloperPayloadEngine()
        let result = try engine.run(input: input, operation: .appIconset)
        let directory = try #require(result.outputURLs.first)
        #expect(directory.pathExtension == "appiconset")
        let undoFiles = try #require(result.undoURLs)
        #expect(undoFiles.count == 11)
        #expect(undoFiles.allSatisfy { $0.deletingLastPathComponent().standardizedFileURL.path == directory.standardizedFileURL.path })
        let userFile = directory.appendingPathComponent("User Notes.txt")
        try Data("keep this user file".utf8).write(to: userFile)
        #expect(!undoFiles.contains(userFile))
        let manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("Contents.json"))) as? [String: Any])
        let slots = try #require(manifest["images"] as? [[String: String]])
        #expect(slots.count == 10)
        for slot in slots {
            #expect(slot["idiom"] == "mac"); #expect(slot["scale"] != "3x")
            let pixels = Int(slot["size"]!.components(separatedBy: "x")[0])! * (slot["scale"] == "2x" ? 2 : 1)
            let image = try #require(CGImageSourceCreateWithURL(directory.appendingPathComponent(slot["filename"]!) as CFURL, nil))
            let decoded = try #require(CGImageSourceCreateImageAtIndex(image, 0, nil))
            #expect(decoded.width == pixels && decoded.height == pixels)
        }
        let again = try engine.run(input: input, operation: .appIconset)
        #expect(again.outputURLs[0] != directory)
        #expect(try Data(contentsOf: input) == before)
    }
    @Test func appIconsetRejectsUndersizedSources() throws {
        let folder = try workspace(); defer { try? FileManager.default.removeItem(at: folder) }
        #expect(throws: (any Error).self) { try DeveloperPayloadEngine().run(input: image(in: folder, size: 64), operation: .appIconset) }
    }
    @Test func appIconsetRejectsNearlySquareSourceBeforeThumbnailRounding() throws {
        let folder = try workspace(); defer { try? FileManager.default.removeItem(at: folder) }
        let context = try #require(CGContext(data: nil, width: 2049, height: 2048, bitsPerComponent: 8, bytesPerRow: 2049 * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0.3, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 2049, height: 2048))
        let source = folder.appendingPathComponent("almost-square.png")
        try NativeConverter.encode(#require(context.makeImage()), to: source, format: .png, quality: 1)
        #expect(throws: (any Error).self) { try DeveloperPayloadEngine().run(input: source, operation: .appIconset) }
    }
    @Test(.enabled(if: EngineEnvironment.discover().resvgURL != nil, "Requires resvg"))
    func minifiedSVGRendersIdenticalPixels() throws {
        let folder = try workspace(); defer { try? FileManager.default.removeItem(at: folder) }
        let source = try write(##"<svg xmlns="http://www.w3.org/2000/svg" width="120" height="100"><path d="M 5,5 L 110, 8 C 80,20 40,90 12,95 Z" fill="#1EC8B8"/><circle cx="50" cy="40" r="12" fill="purple"/></svg>"##, "shapes.svg", in: folder)
        let minified = try DeveloperPayloadEngine().run(input: source, operation: .minifySVG).outputURLs[0]
        let engine = ConversionEngine(environment: .discover())
        let originalPNG = try engine.run(.init(input: source, operation: .convert(.png))).outputURLs[0]
        let minifiedPNG = try engine.run(.init(input: minified, operation: .convert(.png))).outputURLs[0]
        let original = try NativeConverter.decodedImage(originalPNG), result = try NativeConverter.decodedImage(minifiedPNG)
        #expect(original.width == result.width && original.height == result.height)
        #expect((original.dataProvider?.data as Data?) == (result.dataProvider?.data as Data?))
    }
    @Test func paletteReturnsActualColorsAndReopenableCard() throws {
        let folder = try workspace(); defer { try? FileManager.default.removeItem(at: folder) }
        let result = try DeveloperPayloadEngine().run(input: image(in: folder), operation: .extractPalette)
        let code = try String(contentsOf: #require(result.outputURLs.first { $0.pathExtension == "txt" }), encoding: .utf8)
        #expect(code.contains("#FF0000")); #expect(code.contains("#0000FF")); #expect(code.contains("Color("))
        let image = try #require(result.outputURLs.first { $0.pathExtension == "png" })
        #expect(CGImageSourceCreateWithURL(image as CFURL, nil) != nil)
    }
    @Test func SVGPathMinificationPreservesExactNumericTokens() throws {
        let folder = try workspace(); defer { try? FileManager.default.removeItem(at: folder) }
        let input = try write(#"<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40"><!--removed--><path d="M 0, 0 L 1e-3,2.000 L10-5 Z" fill="red"/></svg>"#, "drawing.svg", in: folder)
        let result = try DeveloperPayloadEngine().run(input: input, operation: .minifySVG)
        let text = try String(contentsOf: result.outputURLs[0], encoding: .utf8)
        #expect(text.contains("1e-3")); #expect(text.contains("2.000")); #expect(!text.contains("removed"))
        #expect(text.contains("M0 0L1e-3 2.000L10 -5Z"))
    }
    @Test(arguments: [#"<script>alert(1)</script>"#, #"<image href="file:///etc/passwd"/>"#, #"<rect style="fill:u&#114;l(file:///private.png)"/>"#, #"<foreignObject/>"#, #"<path onclick="bad()" d="M0 0"/>"#])
    func SVGActiveOrExternalContentIsRejected(_ snippet: String) throws {
        let folder = try workspace(); defer { try? FileManager.default.removeItem(at: folder) }
        let input = try write("<svg xmlns=\"http://www.w3.org/2000/svg\">\(snippet)</svg>", "unsafe.svg", in: folder)
        #expect(throws: (any Error).self) { try DeveloperPayloadEngine().run(input: input, operation: .minifySVG) }
    }
}
