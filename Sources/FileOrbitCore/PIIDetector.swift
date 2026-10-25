import Foundation
import NaturalLanguage
import Darwin

public enum PrivacyKind: String, CaseIterable, Sendable {
    case email, phone, address, card, ipAddress, apiKey, manual
    public var title: String {
        switch self {
        case .email: return "Email address"
        case .phone: return "Phone number"
        case .address: return "Possible postal address"
        case .card: return "Payment card"
        case .ipAddress: return "IP address"
        case .apiKey: return "Possible API key"
        case .manual: return "Added region"
        }
    }
}

/// Token ranges are ephemeral OCR evidence. Persisted review models carry only categories and boxes.
struct PrivacyMatch: Equatable, Sendable {
    let kind: PrivacyKind
    let range: NSRange
}

enum PIIDetector {
    static func matches(in text: String) -> [PrivacyMatch] {
        guard !text.isEmpty, text.utf16.count <= 100_000 else { return [] }
        let value = text as NSString
        var found: [PrivacyMatch] = []
        func add(_ pattern: String, kind: PrivacyKind, validate: (String) -> Bool = { _ in true }) {
            guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return }
            for match in expression.matches(in: text, range: NSRange(location: 0, length: value.length)) {
                guard validate(value.substring(with: match.range)) else { continue }
                found.append(PrivacyMatch(kind: kind, range: match.range))
            }
        }
        add(#"(?<![\w.+-])[A-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Z0-9](?:[A-Z0-9-]*[A-Z0-9])?(?:\.[A-Z0-9](?:[A-Z0-9-]*[A-Z0-9])?)+"#, kind: .email)
        add(#"(?<![A-Za-z0-9_])(?:sk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})(?![A-Za-z0-9_])"#, kind: .apiKey)
        add(#"(?<!\d)(?:\d[ -]?){12,18}\d(?![ -]?\d)"#, kind: .card, validate: validCard)
        add(#"(?<![\w.])(?:\d{1,3}\.){3}\d{1,3}(?![\w.])"#, kind: .ipAddress) { validIP($0, family: AF_INET) }
        add(#"(?<![\w:])(?:[0-9a-f]{0,4}:){2,7}[0-9a-f]{0,4}(?![\w:])"#, kind: .ipAddress) { validIP($0, family: AF_INET6) }
        add(#"(?<![\w])(?:\+\d{1,3}[ .-]?)?(?:\(\d{2,4}\)|\d{2,4})[ .-]\d{3,4}[ .-]\d{3,4}(?:\s*(?:ext\.?|x)\s*\d{1,6})?(?!\d)"#, kind: .phone) {
            let count = $0.filter(\.isNumber).count
            return (7...18).contains(count)
        }
        add(#"(?<![\w])(?:\+\d{8,15}|\d{10})(?![\w])"#, kind: .phone)
        add(#"\b\d{1,6}\s+(?:[\p{L}0-9.'-]+\s+){1,6}(?:Street|St\.?|Avenue|Ave\.?|Road|Rd\.?|Lane|Ln\.?|Drive|Dr\.?|Boulevard|Blvd\.?|Court|Ct\.?|Way|Place|Pl\.?|Terrace|Ter\.?)\b(?:\s+(?:Apt|Suite|Unit|#)\s*[\w-]+)?(?:,\s*[\p{L}][\p{L} .\x27-]{0,50},\s*[A-Z]{2}\s+\d{5}(?:-\d{4})?)?"#, kind: .address)
        // A place name alone is not private. Use NLTagger only to extend a detected street address
        // to an adjacent city, so ordinary references such as “Paris is lovely” remain untouched.
        if found.contains(where: { $0.kind == .address }) {
            let tagger = NLTagger(tagSchemes: [.nameType]); tagger.string = text
            tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType,
                                 options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, range in
                guard tag == .placeName else { return true }
                let place = NSRange(range, in: text)
                for index in found.indices where found[index].kind == .address {
                    let streetEnd = NSMaxRange(found[index].range)
                    guard place.location >= streetEnd, place.location - streetEnd <= 4 else { continue }
                    let separator = value.substring(with: NSRange(location: streetEnd, length: place.location - streetEnd))
                    guard separator.allSatisfy({ $0 == " " || $0 == "," }) else { continue }
                    found[index] = PrivacyMatch(kind: .address, range: NSUnionRange(found[index].range, place))
                }
                return true
            }
        }
        // More specific matches win over broad phone-like fragments, but overlapping different
        // boxes remain acceptable: the review surface can display/clear them explicitly.
        return found.filter { candidate in
            candidate.kind != .phone || !found.contains { $0.kind != .phone && NSIntersectionRange(candidate.range, $0.range).length > 0 }
        }.sorted { $0.range.location == $1.range.location ? $0.range.length > $1.range.length : $0.range.location < $1.range.location }
    }

    private static func validCard(_ text: String) -> Bool {
        let digits = text.compactMap(\.wholeNumberValue)
        guard (13...19).contains(digits.count), Set(digits).count > 1 else { return false }
        let sum = digits.reversed().enumerated().reduce(0) { total, entry in
            let doubled = entry.offset % 2 == 1 ? entry.element * 2 : entry.element
            return total + (doubled > 9 ? doubled - 9 : doubled)
        }
        return sum % 10 == 0
    }
    private static func validIP(_ text: String, family: Int32) -> Bool {
        var storage = in6_addr()
        return text.withCString { inet_pton(family, $0, &storage) } == 1
    }
}
