// Copyright © 2017-2026 Robert Horrion.

import Foundation

enum XMLCodec {
    static func escapeText(_ string: String) -> String {
        var result = ""
        result.reserveCapacity(string.count)
        for character in string {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            default: result.append(character)
            }
        }
        return result
    }

    static func escapeAttribute(_ string: String) -> String {
        var result = ""
        result.reserveCapacity(string.count)
        for character in string {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case "\"": result += "&quot;"
            case "\n": result += "&#10;"
            case "\r": result += "&#13;"
            case "\t": result += "&#9;"
            default: result.append(character)
            }
        }
        return result
    }

    static func containsIllegalXMLCharacter(_ string: String) -> Bool {
        string.unicodeScalars.contains { scalar in
            let value = scalar.value
            let legal = value == 0x9 || value == 0xA || value == 0xD
                || (value >= 0x20 && value <= 0xD7FF)
                || (value >= 0xE000 && value <= 0xFFFD)
                || (value >= 0x10000 && value <= 0x10FFFF)
            return !legal
        }
    }

    static func formatDecimal(_ value: Double) -> String {
        let rendered = String(value)
        guard rendered.contains("e") || rendered.contains("E") else { return rendered }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 16
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = false
        formatter.decimalSeparator = "."
        return formatter.string(from: NSNumber(value: value)) ?? rendered
    }

    static func formatInteger(_ value: Int) -> String {
        String(value)
    }

    static func formatYear(_ year: Int) -> String {
        let sign = year < 0 ? "-" : ""
        let digits = String(abs(year))
        if digits.count >= 4 { return sign + digits }
        return sign + String(repeating: "0", count: 4 - digits.count) + digits
    }

    static func formatDate(_ date: Date) -> String {
        // Date's binary fraction is not exact at the nanosecond, so snap to the
        // nearest microsecond before formatting. GPX uses fractional seconds for
        // millisecond track logs; microsecond resolution covers that without noise.
        let rounded = Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1_000_000).rounded() / 1_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .nanosecond],
            from: rounded
        )
        let base = String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0,
            parts.hour ?? 0,
            parts.minute ?? 0,
            parts.second ?? 0
        )
        let microseconds = Int((Double(parts.nanosecond ?? 0) / 1_000).rounded())
        guard (1...999_999).contains(microseconds) else { return base + "Z" }
        var fraction = String(format: "%06d", microseconds)
        while fraction.last == "0" {
            fraction.removeLast()
        }
        return base + "." + fraction + "Z"
    }

    static func decimal(_ raw: String, element: String) throws -> Double {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.range(of: #"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$"#, options: .regularExpression) != nil,
              let value = Double(text),
              value.isFinite
        else {
            throw GPXError(reason: .invalidValue(element: element, value: raw, expected: "a decimal number"))
        }
        return value
    }

    static func integer(_ raw: String, element: String) throws -> Int {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.range(of: #"^[+-]?\d+$"#, options: .regularExpression) != nil,
              let value = Int(text)
        else {
            throw GPXError(reason: .invalidValue(element: element, value: raw, expected: "an integer"))
        }
        return value
    }

    static func nonNegativeInteger(_ raw: String, element: String) throws -> Int {
        let value = try integer(raw, element: element)
        guard value >= 0 else {
            throw GPXError(reason: .invalidValue(element: element, value: raw, expected: "a non-negative integer"))
        }
        return value
    }

    static func date(_ raw: String, element: String) throws -> Date {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^(-?\d{4,})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?(Z|z|([+-])(\d{2}):(\d{2}))?$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.range.location != NSNotFound
        else {
            throw GPXError(reason: .invalidValue(element: element, value: raw, expected: "an ISO 8601 date and time"))
        }

        func capture(_ index: Int) -> String? {
            let range = match.range(at: index)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
            return String(text[swiftRange])
        }

        guard let year = Int(capture(1) ?? ""),
              let month = Int(capture(2) ?? ""),
              let day = Int(capture(3) ?? ""),
              let hour = Int(capture(4) ?? ""),
              let minute = Int(capture(5) ?? ""),
              let second = Int(capture(6) ?? "")
        else {
            throw GPXError(reason: .invalidValue(element: element, value: raw, expected: "an ISO 8601 date and time"))
        }

        var nanosecond = 0
        if let fraction = capture(7) {
            let padded = (fraction + String(repeating: "0", count: 9)).prefix(9)
            nanosecond = Int(padded) ?? 0
        }

        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        components.nanosecond = nanosecond
        guard var date = components.date else {
            throw GPXError(reason: .invalidValue(element: element, value: raw, expected: "a real calendar date and time"))
        }

        if let sign = capture(9), let zoneHour = Int(capture(10) ?? ""), let zoneMinute = Int(capture(11) ?? "") {
            guard (0...23).contains(zoneHour), (0...59).contains(zoneMinute) else {
                throw GPXError(reason: .invalidValue(element: element, value: raw, expected: "a timezone offset"))
            }
            let offset = (sign == "-" ? -1 : 1) * (zoneHour * 3600 + zoneMinute * 60)
            date = date.addingTimeInterval(TimeInterval(-offset))
        }
        return date
    }

    static func year(_ raw: String, element: String) throws -> Int {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^(-?\d{4,})(?:Z|z|[+-]\d{2}:\d{2})?$"#
        guard text.range(of: pattern, options: .regularExpression) != nil else {
            throw GPXError(reason: .invalidValue(element: element, value: raw, expected: "a four-digit year"))
        }
        let digits = text.prefix { character in
            character == "-" || character.isNumber
        }
        guard let year = Int(digits) else {
            throw GPXError(reason: .invalidValue(element: element, value: raw, expected: "a four-digit year"))
        }
        return year
    }

    static func prefix(of rawName: String) -> String? {
        guard let index = rawName.firstIndex(of: ":"), index != rawName.startIndex else { return nil }
        return String(rawName[..<index])
    }

    static func localName(_ rawName: String) -> String {
        guard let index = rawName.lastIndex(of: ":") else { return rawName }
        return String(rawName[rawName.index(after: index)...])
    }

    /// Copies ancestor namespace declarations onto a stored extension element so the subtree still resolves after it leaves the original document.
    static func declaringInheritedNamespaces(
        _ element: XMLElement,
        parentScope: [String: String],
        documentNamespace: String
    ) -> XMLElement {
        var copy = element
        let declared = declaredPrefixes(in: copy)
        for prefix in usedPrefixes(in: copy).subtracting(declared).sorted() {
            guard let uri = parentScope[prefix], !uri.isEmpty else { continue }
            let attributeName = "xmlns:\(prefix)"
            if !copy.attributes.contains(where: { $0.name == attributeName }) {
                copy.attributes.append(XMLAttribute(name: attributeName, value: uri))
            }
        }
        if prefix(of: copy.name) == nil,
           !copy.attributes.contains(where: { $0.name == "xmlns" }),
           let inherited = parentScope[""],
           !inherited.isEmpty,
           inherited != documentNamespace,
           inherited != GPX.Version.v1_0.namespaceURI,
           inherited != GPX.Version.v1_1.namespaceURI
        {
            copy.attributes.append(XMLAttribute(name: "xmlns", value: inherited))
        }
        return copy
    }

    static func isForeignExtension(_ element: XMLElement, version: GPX.Version) -> Bool {
        if let defaultNamespace = element.attributes.first(where: { $0.name == "xmlns" })?.value {
            return !defaultNamespace.isEmpty && defaultNamespace != version.namespaceURI
        }
        if let prefix = prefix(of: element.name) {
            let declaration = "xmlns:\(prefix)"
            guard let uri = element.attributes.first(where: { $0.name == declaration })?.value else {
                return false
            }
            return !uri.isEmpty && uri != version.namespaceURI
        }
        return false
    }

    private static func usedPrefixes(in element: XMLElement) -> Set<String> {
        var prefixes: Set<String> = []
        func walk(_ element: XMLElement) {
            if let prefix = prefix(of: element.name) {
                prefixes.insert(prefix)
            }
            for attribute in element.attributes where attribute.name != "xmlns" && !attribute.name.hasPrefix("xmlns:") {
                if let prefix = prefix(of: attribute.name) {
                    prefixes.insert(prefix)
                }
            }
            for child in element.children {
                if case .element(let child) = child {
                    walk(child)
                }
            }
        }
        walk(element)
        return prefixes
    }

    private static func declaredPrefixes(in element: XMLElement) -> Set<String> {
        var prefixes: Set<String> = []
        func walk(_ element: XMLElement) {
            for attribute in element.attributes where attribute.name.hasPrefix("xmlns:") {
                prefixes.insert(String(attribute.name.dropFirst(6)))
            }
            for child in element.children {
                if case .element(let child) = child {
                    walk(child)
                }
            }
        }
        walk(element)
        return prefixes
    }
}
