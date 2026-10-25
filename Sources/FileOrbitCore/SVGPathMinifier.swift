import Foundation

enum SVGPathMinifier {
    static func minify(_ data: Data) throws -> Data {
        guard data.count <= 4_194_304, let text = String(data: data, encoding: .utf8),
              !["<!doctype", "<!entity", "<?xml-stylesheet"].contains(where: text.lowercased().contains) else {
            throw ConversionError.invalidInput("SVG must be UTF-8, at most 4 MB, and contain no DTD, entity declaration or linked stylesheet.")
        }
        let validator = XMLBoundsValidator(), parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false; parser.delegate = validator
        guard parser.parse(), !validator.rejected else { throw ConversionError.invalidInput("SVG is malformed, too deeply nested, or contains too many elements.") }
        let document = try XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever])
        guard let root = document.rootElement(), root.localName?.lowercased() == "svg" else { throw ConversionError.invalidInput("The file does not contain an SVG root element.") }
        try visit(root)
        let output = document.xmlData(options: [.nodeCompactEmptyElement])
        let check = XMLParser(data: output); check.shouldResolveExternalEntities = false
        guard check.parse() else { throw ConversionError.failed("The minified SVG did not validate.") }
        return output
    }
    private static func visit(_ element: XMLElement) throws {
        let forbidden: Set<String> = ["script", "foreignobject", "iframe", "object", "embed", "audio", "video", "animate", "animatemotion", "animatetransform", "set", "handler"]
        guard !forbidden.contains((element.localName ?? "").lowercased()) else { throw unsafe() }
        for attribute in element.attributes ?? [] {
            let name = (attribute.localName ?? attribute.name ?? "").lowercased(), value = attribute.stringValue ?? ""
            guard !name.hasPrefix("on"), (attribute.name ?? "").lowercased() != "xml:base" else { throw unsafe() }
            if ["href", "src"].contains(name), !value.isEmpty, !value.hasPrefix("#") { throw unsafe() }
            if name == "style" || value.lowercased().contains("url") { try validateCSS(value) }
            if name == "d", element.localName?.lowercased() == "path" { attribute.stringValue = try minifyPath(value) }
        }
        if element.localName?.lowercased() == "style" { try validateCSS(element.stringValue ?? "") }
        for child in element.children ?? [] {
            if child.kind == .comment { child.detach() }
            else if let nested = child as? XMLElement { try visit(nested) }
        }
    }
    private static func validateCSS(_ text: String) throws {
        let lower = text.lowercased()
        guard !lower.contains("\\"), !lower.contains("@"), !lower.contains("expression"), !lower.contains("javascript"), !lower.contains("/*") else { throw unsafe() }
        let expression = try NSRegularExpression(pattern: #"url\s*\(([^)]*)\)"#, options: [.caseInsensitive])
        let matches = expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var residue = text
        for match in matches.reversed() {
            guard let range = Range(match.range(at: 1), in: text), let fullRange = Range(match.range, in: residue) else { throw unsafe() }
            let value = text[range].trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n\"'"))
            guard value.hasPrefix("#"), value.count > 1, !value.contains(where: { $0.isWhitespace }) else { throw unsafe() }
            residue.removeSubrange(fullRange)
        }
        guard !residue.lowercased().contains("url") else { throw unsafe() }
        // CSS can reference images through string arguments without url(), e.g.
        // image-set("https://..."). Permit only known non-resource functions.
        let functions = try NSRegularExpression(pattern: #"([a-z][a-z0-9-]*)\s*\("#, options: [.caseInsensitive])
        let allowed: Set<String> = ["rgb", "rgba", "hsl", "hsla", "hwb", "lab", "lch", "oklab", "oklch", "color", "color-mix", "calc", "min", "max", "clamp", "matrix", "matrix3d", "translate", "translatex", "translatey", "translatez", "rotate", "rotatex", "rotatey", "rotatez", "scale", "scalex", "scaley", "scalez", "skew", "skewx", "skewy"]
        for match in functions.matches(in: residue, range: NSRange(residue.startIndex..., in: residue)) {
            guard let range = Range(match.range(at: 1), in: residue), allowed.contains(residue[range].lowercased()) else { throw unsafe() }
        }
    }
    private static func unsafe() -> ConversionError { .unsupported("SVG minification accepts static self-contained artwork only. Active content, external references and unsupported CSS are rejected.") }
    static func minifyPath(_ text: String) throws -> String {
        let regex = try NSRegularExpression(pattern: #"[MmZzLlHhVvCcSsQqTtAa]|[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?"#)
        let range = NSRange(text.startIndex..., in: text), matches = regex.matches(in: text, range: range)
        var previous = text.startIndex, tokens: [String] = []
        for match in matches {
            guard let range = Range(match.range, in: text) else { throw invalidPath() }
            let gap = text[previous..<range.lowerBound], token = String(text[range])
            guard gap.allSatisfy({ [" ", "\t", "\r", "\n", ","].contains($0) }), gap.filter({ $0 == "," }).count <= 1 else { throw invalidPath() }
            if gap.contains(",") {
                // Comma-wsp separates numbers only: never before the first
                // argument, before a command, after a close or at end of data.
                guard let last = tokens.last, last.first?.isLetter != true, token.first?.isLetter != true else { throw invalidPath() }
            }
            tokens.append(token); previous = range.upperBound
        }
        guard text[previous...].allSatisfy({ [" ", "\t", "\r", "\n"].contains($0) }) else { throw invalidPath() }
        guard !tokens.isEmpty else { return "" }
        func command(_ token: String) -> Bool { token.count == 1 && token.first?.isLetter == true }
        guard ["M", "m"].contains(tokens[0]) else { throw invalidPath() }
        let arities: [String: Int] = ["m": 2, "l": 2, "h": 1, "v": 1, "c": 6, "s": 4, "q": 4, "t": 2, "a": 7, "z": 0]
        var index = 0
        while index < tokens.count {
            guard command(tokens[index]), let count = arities[tokens[index].lowercased()] else { throw invalidPath() }
            let current = tokens[index].lowercased(); index += 1; let start = index
            while index < tokens.count, !command(tokens[index]) {
                guard let number = Double(tokens[index]), number.isFinite else { throw invalidPath() }; index += 1
            }
            let actual = index - start
            if count == 0 { guard actual == 0 else { throw invalidPath() } }
            else {
                guard actual > 0, actual % count == 0 else { throw invalidPath() }
                if current == "a" {
                    for group in stride(from: start, to: index, by: 7) {
                        guard ["0", "1"].contains(tokens[group + 3]), ["0", "1"].contains(tokens[group + 4]), (Double(tokens[group]) ?? -1) >= 0, (Double(tokens[group + 1]) ?? -1) >= 0 else { throw invalidPath() }
                    }
                }
            }
        }
        var output = "", wasNumber = false
        for token in tokens {
            let isCommand = command(token)
            if !isCommand, wasNumber { output += " " }
            output += token; wasNumber = !isCommand
        }
        return output
    }
    private static func invalidPath() -> ConversionError { .invalidInput("The SVG contains unsupported or malformed path data; geometry was not approximated.") }
}

private final class XMLBoundsValidator: NSObject, XMLParserDelegate {
    var depth = 0, count = 0, rejected = false
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        depth += 1; count += 1
        if depth > 48 || count > 50_000 { rejected = true; parser.abortParsing() }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) { depth -= 1 }
}
