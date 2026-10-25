import Foundation

/// A deliberately bounded YAML 1.2 core subset: block mappings/sequences, JSON flow
/// containers, quoted strings and core scalars. No tags, aliases or implicit dates.
enum SafeYAML {
    struct Line { var indent: Int; var text: String }
    static func parse(_ text: String) throws -> StructuredValue {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("{") || clean.hasPrefix("[") { return try StructuredDocument.read(Data(clean.utf8), format: .json) }
        var lines: [Line] = []
        for raw in text.components(separatedBy: .newlines) {
            let indent = raw.prefix { $0 == " " }.count
            guard !raw.prefix(while: { $0 == " " || $0 == "\t" }).contains("\t") else { throw error("Use spaces, not tabs, for YAML indentation.") }
            let content = stripComment(String(raw.dropFirst(indent))).trimmingCharacters(in: .whitespaces)
            if content.isEmpty { continue }
            guard content != "---", content != "...", !content.hasPrefix("%") else { throw error("YAML directives and multi-document streams are not supported.") }
            lines.append(Line(indent: indent, text: content))
            guard lines.count <= StructuredDocument.maximumNodes else { throw error("This YAML has too many lines.") }
        }
        guard let first = lines.first, first.indent == 0 else { throw error("YAML must begin with an unindented value.") }
        var parser = Parser(lines: lines)
        let value = try parser.block(indent: 0, depth: 0)
        guard parser.index == parser.lines.count else { throw error("Unexpected YAML indentation or extra root values.") }
        return value
    }
    static func error(_ text: String) -> ConversionError { .invalidInput(text) }
    static func stripComment(_ text: String) -> String {
        var quote: Character?, escaped = false, result = "", previous: Character?
        for char in text {
            if escaped { escaped = false; result.append(char); previous = char; continue }
            if quote == "\"", char == "\\" { escaped = true; result.append(char); previous = char; continue }
            if let active = quote { if char == active { quote = nil } }
            else if char == "\"" || char == "'" { quote = char }
            else if char == "#", previous == nil || previous?.isWhitespace == true { break }
            result.append(char); previous = char
        }
        return result
    }
    static func pair(_ text: String) -> (String, String)? {
        var quote: Character?, escaped = false
        var index = text.startIndex
        while index < text.endIndex {
            let char = text[index], next = text.index(after: index)
            if escaped { escaped = false }
            else if quote == "\"", char == "\\" { escaped = true }
            else if let active = quote { if char == active { quote = nil } }
            else if char == "\"" || char == "'" { quote = char }
            else if char == ":", next == text.endIndex || text[next].isWhitespace {
                return (String(text[..<index]).trimmingCharacters(in: .whitespaces), String(text[next...]).trimmingCharacters(in: .whitespaces))
            }
            index = next
        }
        return nil
    }
    static func scalar(_ text: String) throws -> StructuredValue {
        guard !text.isEmpty else { return .null }
        if text.hasPrefix("\"") { return try StructuredDocument.read(Data(text.utf8), format: .json) }
        if text.hasPrefix("'") {
            guard text.count >= 2, text.hasSuffix("'") else { throw error("Unterminated YAML single-quoted string.") }
            let inner = String(text.dropFirst().dropLast())
            var output = "", index = inner.startIndex
            while index < inner.endIndex {
                let char = inner[index]; index = inner.index(after: index)
                if char == "'" {
                    guard index < inner.endIndex, inner[index] == "'" else { throw error("Single quotes inside YAML strings must be doubled.") }
                    index = inner.index(after: index)
                }
                output.append(char)
            }
            return .string(output)
        }
        if text.hasPrefix("{") || text.hasPrefix("[") { return try StructuredDocument.read(Data(text.utf8), format: .json) }
        guard !["!", "&", "*", "|", ">", "%", "@", "`", "?", "- "].contains(where: text.hasPrefix), pair(text) == nil else {
            throw error("This YAML feature is outside the safe subset. Use JSON-style flow containers and quoted strings.")
        }
        switch text.lowercased() {
        case "null", "~": return .null
        case "true": return .bool(true)
        case "false": return .bool(false)
        case ".nan", ".inf", "-.inf", "+.inf": throw error("Nonfinite YAML numbers cannot be represented in JSON.")
        default: break
        }
        if text.range(of: #"^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil { return .number(text) }
        if text.range(of: #"^[+-]?(?:[0-9][0-9_]*(?:\.[0-9_]*)?|\.[0-9_]+)(?:[eE][+-]?[0-9_]+)?$|^[+-]?0[xob][0-9a-fA-F_]+$"#, options: .regularExpression) != nil {
            throw error("This YAML number syntax is outside the JSON-compatible subset. Use decimal JSON notation or quote it as a string.")
        }
        return .string(text)
    }
    struct Parser {
        var lines: [Line]
        var index = 0
        func isSequence(_ text: String) -> Bool { text == "-" || text.hasPrefix("- ") }
        mutating func block(indent: Int, depth: Int) throws -> StructuredValue {
            guard depth <= StructuredDocument.maximumDepth, index < lines.count, lines[index].indent == indent else { throw error("YAML nesting or indentation is invalid.") }
            if isSequence(lines[index].text) {
                var values: [StructuredValue] = []
                while index < lines.count, lines[index].indent == indent, isSequence(lines[index].text) {
                    let rest = String(lines[index].text.dropFirst()).trimmingCharacters(in: .whitespaces)
                    if !rest.hasPrefix("{"), !rest.hasPrefix("["), pair(rest) != nil {
                        lines[index] = Line(indent: indent + 2, text: rest)
                        values.append(try block(indent: indent + 2, depth: depth + 1))
                    } else {
                        index += 1
                        if rest.isEmpty, index < lines.count, lines[index].indent > indent { values.append(try block(indent: lines[index].indent, depth: depth + 1)) }
                        else { values.append(try scalar(rest)) }
                    }
                }
                return .array(values)
            }
            if pair(lines[index].text) != nil {
                var fields: [String: StructuredValue] = [:]
                while index < lines.count, lines[index].indent == indent, !isSequence(lines[index].text) {
                    guard let (rawKey, rest) = pair(lines[index].text) else { throw error("Expected a YAML mapping field.") }
                    let key: String
                    if rawKey.hasPrefix("'") || rawKey.hasPrefix("\"") {
                        guard case .string(let decoded) = try scalar(rawKey) else { throw error("YAML object keys must be strings.") }; key = decoded
                    } else {
                        guard !rawKey.isEmpty, !rawKey.contains(where: { "!&*{}[],?".contains($0) }), case .string = try scalar(rawKey) else { throw error("YAML object keys must be strings. Quote numeric or boolean keys explicitly.") }; key = rawKey
                    }
                    guard fields[key] == nil else { throw error("Duplicate YAML object key: \(key.prefix(80)).") }
                    index += 1
                    if rest.isEmpty, index < lines.count, lines[index].indent > indent { fields[key] = try block(indent: lines[index].indent, depth: depth + 1) }
                    else { fields[key] = try scalar(rest) }
                }
                return .object(fields)
            }
            let value = try scalar(lines[index].text); index += 1; return value
        }
    }
    static func emit(_ value: StructuredValue, indent: Int = 0) -> String {
        let pad = String(repeating: " ", count: indent)
        func inline(_ value: StructuredValue) -> Bool {
            switch value { case .array(let values): return values.isEmpty; case .object(let fields): return fields.isEmpty; default: return true }
        }
        switch value {
        case .object(let fields) where !fields.isEmpty:
            return fields.keys.sorted().map { key in
                let value = fields[key]!, prefix = pad + StructuredDocument.quoted(key) + ":"
                return inline(value) ? prefix + " " + StructuredDocument.json(value) : prefix + "\n" + emit(value, indent: indent + 2)
            }.joined(separator: "\n")
        case .array(let values) where !values.isEmpty:
            return values.map { inline($0) ? pad + "- " + StructuredDocument.json($0) : pad + "-\n" + emit($0, indent: indent + 2) }.joined(separator: "\n")
        default: return pad + StructuredDocument.json(value)
        }
    }
}
