import Foundation

public enum StructuredFormat: String, CaseIterable, Sendable, Equatable {
    case json, yaml, csv, swift
    public var title: String { self == .swift ? "Swift Codable" : rawValue.uppercased() }
    static func detect(_ url: URL) -> Self? {
        switch url.pathExtension.lowercased() {
        case "json": return .json
        case "yaml", "yml": return .yaml
        case "csv": return .csv
        case "swift": return .swift
        default: return nil
        }
    }
}

/// Numbers retain their original decimal spelling, avoiding Double's 53-bit integer limit.
indirect enum StructuredValue: Sendable, Equatable {
    case object([String: StructuredValue]), array([StructuredValue]), string(String), number(String), bool(Bool), null
}

enum StructuredDocument {
    static let maximumBytes = 8_388_608
    static let maximumDepth = 48
    static let maximumNodes = 100_000
    static func read(_ data: Data, format: StructuredFormat) throws -> StructuredValue {
        guard data.count <= maximumBytes, let text = String(data: data, encoding: .utf8) else {
            throw ConversionError.invalidInput("Structured data must be UTF-8 and no larger than 8 MB.")
        }
        let value: StructuredValue
        switch format {
        case .json: var parser = JSONValueParser(text); value = try parser.parse()
        case .yaml: value = try SafeYAML.parse(text)
        case .csv: value = try FlatCSV.parse(text)
        case .swift: value = try SwiftSchema.template(from: text)
        }
        var count = 0
        try validate(value, depth: 0, count: &count)
        return value
    }
    static func write(_ value: StructuredValue, format: StructuredFormat) throws -> Data {
        var count = 0; try validate(value, depth: 0, count: &count)
        let text: String
        switch format {
        case .json: text = json(value) + "\n"
        case .yaml: text = "# JSON-compatible YAML. Strings are quoted to preserve their types.\n" + SafeYAML.emit(value) + "\n"
        case .csv: text = try FlatCSV.emit(value)
        case .swift: text = try SwiftSchema.generate(value)
        }
        guard text.utf8.count <= maximumBytes else { throw ConversionError.unsupported("The generated payload exceeds the 8 MB limit.") }
        return Data(text.utf8)
    }
    private static func validate(_ node: StructuredValue, depth: Int, count: inout Int) throws {
        count += 1
        guard depth <= maximumDepth, count <= maximumNodes else { throw ConversionError.unsupported("Structured payloads are limited to 48 levels and 100,000 values.") }
        switch node {
        case .object(let fields): for value in fields.values { try validate(value, depth: depth + 1, count: &count) }
        case .array(let values): for value in values { try validate(value, depth: depth + 1, count: &count) }
        default: break
        }
    }
    static func quoted(_ string: String) -> String {
        // Encoding one String cannot fail; the fallback is unreachable for valid Swift strings.
        (try? String(decoding: JSONEncoder().encode(string), as: UTF8.self)) ?? "\"\""
    }
    static func json(_ value: StructuredValue, level: Int = 0) -> String {
        let pad = String(repeating: "  ", count: level), childPad = pad + "  "
        switch value {
        case .null: return "null"
        case .bool(let bool): return bool ? "true" : "false"
        case .number(let number): return number
        case .string(let string): return quoted(string)
        case .array(let values):
            guard !values.isEmpty else { return "[]" }
            return "[\n" + values.map { childPad + json($0, level: level + 1) }.joined(separator: ",\n") + "\n" + pad + "]"
        case .object(let fields):
            guard !fields.isEmpty else { return "{}" }
            return "{\n" + fields.keys.sorted().map { childPad + quoted($0) + ": " + json(fields[$0]!, level: level + 1) }.joined(separator: ",\n") + "\n" + pad + "}"
        }
    }
}

private struct JSONValueParser {
    let bytes: [UInt8]
    var offset = 0
    var nodes = 0
    init(_ text: String) { bytes = Array(text.utf8) }
    mutating func parse() throws -> StructuredValue {
        let value = try value(depth: 0); skipSpace()
        guard offset == bytes.count else { throw bad("Unexpected content after the JSON value.") }
        return value
    }
    mutating func skipSpace() { while offset < bytes.count, [9, 10, 13, 32].contains(bytes[offset]) { offset += 1 } }
    func bad(_ text: String) -> ConversionError { .invalidInput(text + " (byte \(offset + 1))") }
    mutating func take(_ char: UInt8) -> Bool { skipSpace(); if offset < bytes.count, bytes[offset] == char { offset += 1; return true }; return false }
    mutating func value(depth: Int) throws -> StructuredValue {
        nodes += 1; skipSpace()
        guard depth <= StructuredDocument.maximumDepth, nodes <= StructuredDocument.maximumNodes else { throw bad("JSON is too deeply nested or has too many values.") }
        guard offset < bytes.count else { throw bad("A JSON value is missing.") }
        switch bytes[offset] {
        case 123:
            offset += 1; var result: [String: StructuredValue] = [:]
            if take(125) { return .object(result) }
            repeat {
                skipSpace(); let key = try string()
                guard result[key] == nil else { throw bad("Duplicate JSON object key: \(key.prefix(80)).") }
                guard take(58) else { throw bad("Expected a colon after the JSON key.") }
                result[key] = try value(depth: depth + 1)
                if take(125) { return .object(result) }
                guard take(44) else { throw bad("Expected a comma between JSON fields.") }
            } while true
        case 91:
            offset += 1; var result: [StructuredValue] = []
            if take(93) { return .array(result) }
            repeat {
                result.append(try value(depth: depth + 1))
                if take(93) { return .array(result) }
                guard take(44) else { throw bad("Expected a comma between JSON values.") }
            } while true
        case 34: return .string(try string())
        case 116: try literal("true"); return .bool(true)
        case 102: try literal("false"); return .bool(false)
        case 110: try literal("null"); return .null
        default:
            let start = offset
            if offset < bytes.count, bytes[offset] == 45 { offset += 1 }
            guard offset < bytes.count else { throw bad("Invalid JSON number.") }
            if bytes[offset] == 48 { offset += 1 }
            else {
                guard (49...57).contains(bytes[offset]) else { throw bad("Invalid JSON value.") }
                while offset < bytes.count, (48...57).contains(bytes[offset]) { offset += 1 }
            }
            if offset < bytes.count, bytes[offset] == 46 {
                offset += 1; let fraction = offset
                while offset < bytes.count, (48...57).contains(bytes[offset]) { offset += 1 }
                guard offset > fraction else { throw bad("A JSON fraction requires digits.") }
            }
            if offset < bytes.count, bytes[offset] == 69 || bytes[offset] == 101 {
                offset += 1
                if offset < bytes.count, bytes[offset] == 43 || bytes[offset] == 45 { offset += 1 }
                let exponent = offset
                while offset < bytes.count, (48...57).contains(bytes[offset]) { offset += 1 }
                guard offset > exponent else { throw bad("A JSON exponent requires digits.") }
            }
            return .number(String(decoding: bytes[start..<offset], as: UTF8.self))
        }
    }
    mutating func literal(_ text: String) throws {
        let target = Array(text.utf8)
        guard offset + target.count <= bytes.count, Array(bytes[offset..<(offset + target.count)]) == target else { throw bad("Invalid JSON literal.") }
        offset += target.count
    }
    mutating func string() throws -> String {
        guard offset < bytes.count, bytes[offset] == 34 else { throw bad("A JSON key must be a quoted string.") }
        let start = offset; offset += 1
        while offset < bytes.count {
            let byte = bytes[offset]; offset += 1
            if byte == 92 { guard offset < bytes.count else { break }; offset += 1 }
            else if byte == 34 {
                guard let value = try? JSONDecoder().decode(String.self, from: Data(bytes[start..<offset])) else { throw bad("Invalid JSON string escape or Unicode.") }
                return value
            }
        }
        throw bad("Unterminated JSON string.")
    }
}
