import Foundation

enum FlatCSV {
    enum State { case start, plain, quoted, closed }
    static func parse(_ text: String) throws -> StructuredValue {
        let bytes = Array(text.utf8); var offset = 0, state = State.start
        var rows: [[String]] = [], row: [String] = [], field: [UInt8] = [], touched = false
        func string(_ bytes: [UInt8]) -> String { String(decoding: bytes, as: UTF8.self) }
        func fail() -> ConversionError { .invalidInput("CSV has inconsistent columns, an invalid quote, or too many rows. Use a UTF-8 table with a unique header row.") }
        while offset < bytes.count {
            let byte = bytes[offset]; touched = true
            switch state {
            case .quoted:
                if byte == 34 {
                    if offset + 1 < bytes.count, bytes[offset + 1] == 34 { field.append(34); offset += 1 }
                    else { state = .closed }
                } else { field.append(byte) }
            case .start, .plain, .closed:
                if byte == 44 { row.append(string(field)); field = []; state = .start }
                else if byte == 10 || byte == 13 {
                    row.append(string(field)); rows.append(row); row = []; field = []; state = .start; touched = false
                    if byte == 13, offset + 1 < bytes.count, bytes[offset + 1] == 10 { offset += 1 }
                    guard rows.count <= 50_001 else { throw fail() }
                } else if byte == 34 {
                    guard state == .start else { throw fail() }; state = .quoted
                } else {
                    guard state != .closed else { throw fail() }; field.append(byte); state = .plain
                }
            }
            offset += 1
        }
        guard state != .quoted else { throw fail() }
        if touched || !row.isEmpty || !field.isEmpty { row.append(string(field)); rows.append(row) }
        guard let header = rows.first, !header.isEmpty, header.count <= 512, header.allSatisfy({ !$0.isEmpty }), Set(header).count == header.count else { throw fail() }
        var values: [StructuredValue] = []
        for row in rows.dropFirst() {
            guard row.count == header.count else { throw fail() }
            values.append(.object(Dictionary(uniqueKeysWithValues: zip(header, row.map(StructuredValue.string)))))
        }
        // An empty table cannot retain its column schema in plain JSON; do not discard it silently.
        guard !values.isEmpty else { throw ConversionError.unsupported("A header-only CSV cannot become JSON without losing its column schema. Add a data row first.") }
        return .array(values)
    }
    static func emit(_ value: StructuredValue) throws -> String {
        guard case .array(let values) = value, !values.isEmpty, case .object(let first) = values[0], !first.isEmpty else {
            throw ConversionError.unsupported("CSV requires a nonempty array of flat records with identical fields.")
        }
        let keys = first.keys.sorted()
        func quoted(_ text: String) -> String { "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var rows = [keys.map(quoted).joined(separator: ",")]
        for value in values {
            guard case .object(let fields) = value, Set(fields.keys) == Set(keys) else { throw ConversionError.unsupported("Every CSV record must have the same fields; no fields were discarded.") }
            let cells = try keys.map { key -> String in
                switch fields[key]! {
                case .string(let text): return quoted(text)
                case .number(let number): return quoted(number)
                case .bool(let bool): return quoted(bool ? "true" : "false")
                default: throw ConversionError.unsupported("CSV cannot preserve nested values or distinguish null from an empty string. Choose JSON or YAML.")
                }
            }
            rows.append(cells.joined(separator: ","))
        }
        return rows.joined(separator: "\r\n") + "\r\n"
    }
}
