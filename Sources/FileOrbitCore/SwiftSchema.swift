import Foundation

/// Swift is parsed as a small declarative schema language; source is never executed.
/// Generated models omit values, and the reverse transform returns placeholders only.
enum SwiftSchema {
    private indirect enum FieldType {
        case primitive(String), object(String), array(FieldType), optional(FieldType)
        var spelling: String {
            switch self {
            case .primitive(let value), .object(let value): return value
            case .array(let item): return "[\(item.spelling)]"
            case .optional(let wrapped): return wrapped.spelling + "?"
            }
        }
    }
    private struct Field { let name: String; let key: String; let type: FieldType }
    private struct Generator {
        var definitions: [String: [Field]] = [:]
        var usedNames = Set<String>()
        var inferenceWork = 0
        mutating func consumeWork(_ count: Int) throws {
            guard count >= 0, count <= 1_000_000 - inferenceWork else { throw failure("This schema exceeds the inference work budget. Use fewer sample records or a narrower set of fields.") }
            inferenceWork += count
        }
        mutating func unique(_ hint: String) throws -> String {
            guard usedNames.count < 512 else { throw failure("Swift model generation is limited to 512 types.") }
            let base = SwiftSchema.identifier(hint, capitalized: true)
            var candidate = base, suffix = 2
            while !usedNames.insert(candidate).inserted { candidate = base + String(suffix); suffix += 1 }
            return candidate
        }
        mutating func infer(_ values: [StructuredValue], hint: String, depth: Int = 0) throws -> FieldType {
            guard depth <= 32 else { throw failure("Swift models are limited to 32 nested types.") }
            try consumeWork(values.count)
            let present = values.filter { $0 != .null }
            guard let first = present.first else { throw failure("A field containing only null has no inferable Codable type. Supply a representative non-null value.") }
            let type: FieldType
            switch first {
            case .string:
                guard present.allSatisfy({ if case .string = $0 { return true }; return false }) else { throw mixed() }; type = .primitive("String")
            case .bool:
                guard present.allSatisfy({ if case .bool = $0 { return true }; return false }) else { throw mixed() }; type = .primitive("Bool")
            case .number:
                let numbers = try present.map { value -> String in guard case .number(let number) = value else { throw mixed() }; return number }
                if numbers.allSatisfy({ Int($0) != nil }) { type = .primitive("Int") }
                else {
                    guard numbers.allSatisfy(SwiftSchema.isExactlyRepresentableDecimal) else { throw failure("A number cannot be represented exactly by Swift Decimal. Keep this payload as JSON/YAML or model that value explicitly as text.") }
                    type = .primitive("Decimal")
                }
            case .array:
                let items = try present.flatMap { value -> [StructuredValue] in guard case .array(let array) = value else { throw mixed() }; return array }
                guard !items.isEmpty else { throw failure("An empty array has no inferable element type. Supply a representative item.") }
                type = .array(try infer(items, hint: hint + "Item", depth: depth + 1))
            case .object:
                let objects = try present.map { value -> [String: StructuredValue] in guard case .object(let object) = value else { throw mixed() }; return object }
                let keySet = Set(objects.flatMap { $0.keys })
                guard keySet.count <= 512 else { throw failure("A Swift model is limited to 512 fields. Split this object into smaller models.") }
                let keys = keySet.sorted(), name = try unique(hint)
                // Reserve the entire key/record cross-product before constructing
                // missing-value columns. Sparse records otherwise amplify a small
                // JSON input into quadratic inference work.
                guard objects.count <= 1_000_000 / max(1, keys.count) else { throw failure("This schema exceeds the inference work budget. Use fewer sample records or a narrower set of fields.") }
                try consumeWork(objects.count * keys.count)
                var fields: [Field] = [], names = Set<String>()
                for key in keys {
                    let base = SwiftSchema.identifier(key, capitalized: false)
                    var fieldName = base, suffix = 2
                    while !names.insert(fieldName).inserted { fieldName = base + String(suffix); suffix += 1 }
                    let fieldType = try infer(objects.map { $0[key] ?? .null }, hint: name + SwiftSchema.identifier(key, capitalized: true), depth: depth + 1)
                    fields.append(Field(name: fieldName, key: key, type: fieldType))
                }
                definitions[name] = fields; type = .object(name)
            case .null: throw mixed()
            }
            return present.count == values.count ? type : .optional(type)
        }
        func mixed() -> ConversionError { failure("Mixed incompatible scalar types cannot be inferred as one Codable property. Normalize the data or write a custom decoder.") }
    }
    static func failure(_ text: String) -> ConversionError { .unsupported(text) }
    static func identifier(_ value: String, capitalized: Bool) -> String {
        let pieces = value.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let ascii = pieces.map { $0.filter { $0.isASCII && ($0.isLetter || $0.isNumber) } }.filter { !$0.isEmpty }
        var result = ascii.enumerated().map { index, text in
            let first = String(text.prefix(1)), rest = String(text.dropFirst())
            return (index == 0 && !capitalized ? first.lowercased() : first.uppercased()) + rest
        }.joined()
        if result.isEmpty { result = capitalized ? "Payload" : "field" }
        if result.first?.isNumber == true { result = (capitalized ? "Payload" : "field") + result }
        let reserved: Set<String> = ["class", "struct", "enum", "protocol", "extension", "func", "var", "let", "return", "import", "if", "else", "case", "switch", "default", "for", "while", "repeat", "do", "catch", "try", "throw", "throws", "rethrows", "in", "where", "as", "is", "self", "Self", "super", "init", "deinit", "subscript", "typealias", "associatedtype", "operator", "static", "public", "private", "fileprivate", "internal", "open", "package", "true", "false", "nil", "Any", "Type", "Protocol", "Codable", "CodingKeys", "String", "Int", "Bool", "Decimal", "Double", "Float", "actor", "async", "await", "some", "any", "inout", "weak", "unowned", "guard", "defer", "break", "continue", "fallthrough", "precedencegroup", "borrowing", "consuming", "distributed", "dynamic", "final", "indirect", "lazy", "mutating", "nonmutating", "optional", "override", "required", "get", "set", "willSet", "didSet", "infix", "prefix", "postfix", "convenience", "isolated", "nonisolated", "sending", "macro"]
        if reserved.contains(result) { result = (capitalized ? "Payload" : "field") + String(result.prefix(1)).uppercased() + result.dropFirst() }
        return String(result.prefix(100))
    }
    static func generate(_ value: StructuredValue) throws -> String {
        var generator = Generator()
        let root: FieldType
        switch value {
        case .object: root = try generator.infer([value], hint: "RootPayload")
        case .array(let values):
            guard !values.isEmpty, values.allSatisfy({ if case .object = $0 { return true }; return false }) else { throw failure("Swift model generation requires an object or a nonempty array of objects.") }
            root = .array(try generator.infer(values, hint: "RootPayloadItem"))
        default: throw failure("Swift model generation requires an object or an array of objects.")
        }
        var lines = ["// FileOrbit Codable schema. No original data values are stored here.", "// Reverse conversion creates a placeholder template, not the original JSON.", "import Foundation", ""]
        if case .array = root { lines += ["typealias RootPayload = \(root.spelling)", ""] }
        let order = generator.definitions.keys.sorted { left, right in
            if left == "RootPayload" { return true }; if right == "RootPayload" { return false }; return left < right
        }
        for name in order {
            let fields = generator.definitions[name]!
            lines.append("struct \(name): Codable {")
            for field in fields { lines.append("    var \(field.name): \(field.type.spelling)") }
            if !fields.isEmpty {
                lines += ["", "    enum CodingKeys: String, CodingKey {"]
                for field in fields { lines.append("        case \(field.name) = \(swiftLiteral(field.key))") }
                lines.append("    }")
            }
            lines += ["}", ""]
        }
        return lines.joined(separator: "\n")
    }

    private struct SchemaField { let name: String; let type: String }
    private struct Schema { var fields: [SchemaField] = []; var fieldNames = Set<String>(); var keys: [String: String] = [:] }
    static func template(from text: String) throws -> StructuredValue {
        var schemas: [String: Schema] = [:], rootAlias: String?, firstName: String?, currentName: String?, codingKeys = false
        var parsedFields = 0
        func captures(_ pattern: String, _ line: String) -> [String]? {
            guard let expression = try? NSRegularExpression(pattern: pattern), let match = expression.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)), match.range.length == line.utf16.count else { return nil }
            return (1..<match.numberOfRanges).map { Range(match.range(at: $0), in: line).map { String(line[$0]) } ?? "" }
        }
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("//") { continue }
            if currentName == nil {
                if line == "import Foundation" { continue }
                if let parts = captures(#"typealias RootPayload = (\[[A-Za-z_][A-Za-z_0-9]*\])"#, line) {
                    guard rootAlias == nil else { throw failure("Duplicate root typealias in Swift schema.") }; rootAlias = parts[0]; continue
                }
                guard let parts = captures(#"(?:public )?struct ([A-Za-z_][A-Za-z_0-9]*): Codable \{"#, line), schemas[parts[0]] == nil else { throw unsupportedSwift() }
                guard schemas.count < 512 else { throw failure("Swift schema input is limited to 512 types.") }
                currentName = parts[0]; if firstName == nil { firstName = parts[0] }; schemas[parts[0]] = Schema(); continue
            }
            guard let name = currentName else { throw unsupportedSwift() }
            if line == "}" {
                if codingKeys { codingKeys = false } else { currentName = nil }; continue
            }
            if codingKeys {
                guard let parts = captures(#"case ([A-Za-z_][A-Za-z_0-9]*) = (\"(?:[^\"\\]|\\.)*\")"#, line), schemas[name]?.keys[parts[0]] == nil,
                      let key = try? decodeSwiftLiteral(parts[1]) else { throw unsupportedSwift() }
                schemas[name]?.keys[parts[0]] = key
            } else if line == "enum CodingKeys: String, CodingKey {" { codingKeys = true }
            else {
                guard let parts = captures(#"(?:var|let) ([A-Za-z_][A-Za-z_0-9]*): ([A-Za-z_0-9\[\]?]+)"#, line), schemas[name]?.fieldNames.contains(parts[0]) == false else { throw unsupportedSwift() }
                guard (schemas[name]?.fields.count ?? 0) < 512, parsedFields < StructuredDocument.maximumNodes else { throw failure("Swift schemas are limited to 512 fields per type and 100,000 total fields.") }
                schemas[name]?.fieldNames.insert(parts[0]); parsedFields += 1
                schemas[name]?.fields.append(SchemaField(name: parts[0], type: parts[1]))
            }
        }
        guard currentName == nil, !codingKeys, let root = rootAlias ?? (schemas["RootPayload"] != nil ? "RootPayload" : firstName), schemas.count <= 512 else { throw unsupportedSwift() }
        for schema in schemas.values {
            guard Set(schema.keys.keys).isSubset(of: Set(schema.fields.map(\.name))), Set(schema.keys.values).count == schema.keys.count else { throw unsupportedSwift() }
            if !schema.keys.isEmpty, schema.keys.count != schema.fields.count { throw failure("Partial CodingKeys mappings would silently omit Swift properties. Declare every property.") }
        }
        var expandedNodes = 0
        func placeholder(_ type: String, visited: Set<String>, depth: Int) throws -> StructuredValue {
            expandedNodes += 1
            guard expandedNodes <= StructuredDocument.maximumNodes else { throw failure("Swift schema templates are limited to 100,000 expanded values. Reduce repeated branches before generating a template.") }
            guard depth <= 32 else { throw failure("Recursive or deeply nested Swift models require a custom template.") }
            if type.hasSuffix("?") { _ = try placeholder(String(type.dropLast()), visited: visited, depth: depth + 1); return .null }
            if type.hasPrefix("["), type.hasSuffix("]") {
                // Include one representative element so the template describes the item schema.
                return .array([try placeholder(String(type.dropFirst().dropLast()), visited: visited, depth: depth + 1)])
            }
            switch type {
            case "String": return .string("")
            case "Bool": return .bool(false)
            case "Int", "Int64", "Int32", "UInt", "UInt64", "Double", "Float", "Decimal": return .number("0")
            default:
                guard !visited.contains(type), let schema = schemas[type] else { throw failure("Unsupported or recursive Swift type: \(type.prefix(80)).") }
                var visited = visited; visited.insert(type); var fields: [String: StructuredValue] = [:]
                for field in schema.fields {
                    let key = schema.keys[field.name] ?? field.name
                    guard fields[key] == nil else { throw failure("Duplicate Swift CodingKeys values would discard a property.") }
                    fields[key] = try placeholder(field.type, visited: visited, depth: depth + 1)
                }
                return .object(fields)
            }
        }
        return try placeholder(root, visited: [], depth: 0)
    }
    private static func isExactlyRepresentableDecimal(_ number: String) -> Bool {
        guard var decimal = Decimal(string: number, locale: Locale(identifier: "en_US_POSIX")),
              !decimal.isNaN, let expected = canonicalNumber(number),
              let actual = canonicalNumber(NSDecimalString(&decimal, Locale(identifier: "en_US_POSIX"))) else { return false }
        return actual == expected
    }
    /// Normalize decimal spelling without converting through binary floating point.
    /// Decimal(string:) can silently round long mantissas, so a successful parse is
    /// insufficient: its exact decimal output must equal the original coefficient.
    private static func canonicalNumber(_ number: String) -> String? {
        let parts = number.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "e" || $0 == "E" })
        guard parts.count <= 2, let first = parts.first else { return nil }
        let explicitExponent: Int
        if parts.count == 2 { guard let value = Int(parts[1]), (-10_000...10_000).contains(value) else { return nil }; explicitExponent = value }
        else { explicitExponent = 0 }
        var mantissa = String(first), negative = false
        if mantissa.hasPrefix("-") { negative = true; mantissa.removeFirst() }
        else if mantissa.hasPrefix("+") { mantissa.removeFirst() }
        let halves = mantissa.split(separator: ".", omittingEmptySubsequences: false)
        guard halves.count <= 2 else { return nil }
        let rawDigits = halves.joined()
        guard !rawDigits.isEmpty, rawDigits.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        var digits = String(rawDigits.drop(while: { $0 == "0" }))
        if digits.isEmpty { return "0" }
        var exponent = explicitExponent - (halves.count == 2 ? halves[1].count : 0)
        while digits.last == "0" { digits.removeLast(); exponent += 1 }
        return (negative ? "-" : "") + digits + "e" + String(exponent)
    }
    private static func swiftLiteral(_ value: String) -> String {
        var output = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 34: output += "\\\""
            case 92: output += "\\\\"
            case 10: output += "\\n"
            case 13: output += "\\r"
            case 9: output += "\\t"
            case 0...31, 127, 0x2028, 0x2029: output += "\\u{" + String(scalar.value, radix: 16) + "}"
            default: output.unicodeScalars.append(scalar)
            }
        }
        return output + "\""
    }
    private static func decodeSwiftLiteral(_ literal: String) throws -> String {
        guard literal.hasPrefix("\""), literal.hasSuffix("\"") else { throw unsupportedSwift() }
        let characters = Array(literal.dropFirst().dropLast().unicodeScalars)
        var index = 0, result = ""
        while index < characters.count {
            let scalar = characters[index]; index += 1
            guard scalar.value == 92 else {
                guard scalar.value >= 32 else { throw unsupportedSwift() }; result.unicodeScalars.append(scalar); continue
            }
            guard index < characters.count else { throw unsupportedSwift() }
            let escape = characters[index]; index += 1
            switch escape.value {
            case 34, 92: result.unicodeScalars.append(escape)
            case 110: result += "\n"
            case 114: result += "\r"
            case 116: result += "\t"
            case 48: result += "\0"
            case 117:
                guard index < characters.count, characters[index].value == 123 else { throw unsupportedSwift() }; index += 1
                var hex = ""
                while index < characters.count, characters[index].value != 125 {
                    hex.unicodeScalars.append(characters[index]); index += 1
                    guard hex.count <= 8 else { throw unsupportedSwift() }
                }
                guard index < characters.count, !hex.isEmpty, let code = UInt32(hex, radix: 16), let decoded = UnicodeScalar(code) else { throw unsupportedSwift() }
                result.unicodeScalars.append(decoded); index += 1
            default: throw unsupportedSwift()
            }
        }
        return result
    }
    private static func unsupportedSwift() -> ConversionError {
        failure("Swift input supports declarative Codable structs, simple properties, complete CodingKeys and a RootPayload array typealias. Functions, initializers, custom decoders and arbitrary Swift are never executed.")
    }
}
