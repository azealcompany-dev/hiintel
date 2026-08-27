import Foundation

enum HTMLText {
    /// Strip tags and entities. Never use this as HTML — display the result as plain text only.
    static func plain(_ html: String) -> String {
        guard !html.isEmpty else { return "" }
        var s = html
        s = s.replacingOccurrences(of: "(?is)<script[^>]*>.*?</script>", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?is)<style[^>]*>.*?</style>", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?i)<br\\s*/?>", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?i)</(?:p|div|h[1-6]|li|ul|ol|tr|td|blockquote)>", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        s = decodeEntities(s)
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeEntities(_ raw: String) -> String {
        var s = raw
        let named: [(String, String)] = [
            ("&nbsp;", " "),
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&apos;", "'"),
            ("&#39;", "'"),
            ("&#x27;", "'"),
            ("&rsquo;", "\u{2019}"),
            ("&lsquo;", "\u{2018}"),
            ("&rdquo;", "\u{201D}"),
            ("&ldquo;", "\u{201C}"),
            ("&mdash;", "\u{2014}"),
            ("&ndash;", "\u{2013}"),
            ("&hellip;", "\u{2026}"),
        ]
        for (entity, replacement) in named {
            s = s.replacingOccurrences(of: entity, with: replacement)
            s = s.replacingOccurrences(of: entity.uppercased(), with: replacement)
        }
        s = decodeNumeric(s, hex: false)
        s = decodeNumeric(s, hex: true)
        return s
    }

    private static func decodeNumeric(_ raw: String, hex: Bool) -> String {
        let pattern = hex ? "&#x([0-9a-fA-F]+);" : "&#([0-9]+);"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return raw }
        let ns = raw as NSString
        let matches = regex.matches(in: raw, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return raw }
        var result = ""
        var cursor = 0
        for match in matches {
            let full = match.range
            if full.location > cursor {
                result += ns.substring(with: NSRange(location: cursor, length: full.location - cursor))
            }
            let digits = ns.substring(with: match.range(at: 1))
            let value = hex ? UInt32(digits, radix: 16) : UInt32(digits)
            if let value, value >= 32, let scalar = UnicodeScalar(value) {
                result.append(Character(scalar))
            }
            cursor = full.location + full.length
        }
        if cursor < ns.length {
            result += ns.substring(from: cursor)
        }
        return result
    }
}
