import Foundation

enum TextProcessor {
    struct Options {
        var cleanURLs: Bool
        var cleanHandles: Bool
        var fixLigatures: Bool
        var expandAbbr: Bool
    }

    static func sanitize(_ text: String, options: Options) -> String {
        var result = text

        // 1. Hyphenation Fix
        // Detects "word- \n next" and joins them
        result = result.replacingOccurrences(of: "([a-zA-Z])- [\\r\\n]+([a-zA-Z])", with: "$1$2", options: .regularExpression)
        result = result.replacingOccurrences(of: "([a-zA-Z])-\\s+[\\r\\n]+([a-zA-Z])", with: "$1$2", options: .regularExpression)

        if options.fixLigatures {
            result = result.replacingOccurrences(of: "f i", with: "fi")
            result = result.replacingOccurrences(of: "f l", with: "fl")
            result = result.replacingOccurrences(of: "f f", with: "ff")
            result = result.replacingOccurrences(of: "n t", with: "nt")
            result = result.replacingOccurrences(of: "f j", with: "fj")
        }

        if options.cleanURLs {
            let regex = try? NSRegularExpression(pattern: "https?://\\S+", options: .caseInsensitive)
            result = regex?.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "[link]") ?? result
        }

        if options.cleanHandles {
            result = result.replacingOccurrences(of: "@\\w+", with: "", options: .regularExpression)
        }

        if options.expandAbbr {
            let abbr = [
                "e.g.": "for example",
                "i.e.": "that is",
                "etc.": "etcetera",
                "vs.": "versus",
                "st.": "street",
                "apt.": "apartment",
                "fig.": "figure",
                "figs.": "figures",
                "vol.": "volume",
                "no.": "number",
                "sec.": "section",
                "eq.": "equation",
                "eqs.": "equations",
                "ref.": "reference",
                "refs.": "references",
                "ch.": "chapter",
                "pp.": "pages",
                "p.": "page",
            ]
            for (k, v) in abbr {
                // FIX: Escape the period and enforce a Word Boundary (\b)
                // This ensures "host." doesn't trigger the "st." replacement.
                let escapedKey = k.replacingOccurrences(of: ".", with: "\\.")
                let pattern = "\\b\(escapedKey)"

                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    result = regex.stringByReplacingMatches(
                        in: result,
                        range: NSRange(result.startIndex..., in: result),
                        withTemplate: v
                    )
                }
            }
        }

        // Final purification: Remove placeholders and purely symbolic noise
        let symbols = ["\u{FFFC}", "￼", "•", "●", "▪", "◦", "‣", "⁃", "□", "▪"]
        for s in symbols {
            result = result.replacingOccurrences(of: s, with: "")
        }

        // Remove multiple consecutive newlines which often represent page gaps
        result = result.replacingOccurrences(of: "(\\n\\s*){2,}", with: "\n", options: .regularExpression)

        let cleaned = result.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        // Reduce multiple spaces to single space
        return cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
