import Foundation

struct TextProcessor {
    struct Options {
        var cleanURLs: Bool
        var cleanHandles: Bool
        var fixLigatures: Bool
        var expandAbbr: Bool
    }
    
    static func sanitize(_ text: String, options: Options) -> String {
        var result = text
        
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
                "apt.": "apartment"
            ]
            for (k, v) in abbr {
                result = result.replacingOccurrences(of: k, with: v, options: .caseInsensitive)
            }
        }
        
        // Final purification: Remove placeholders and purely symbolic noise
        let symbols = ["\u{FFFC}", "￼", "•", "●", "▪", "◦", "‣", "⁃"]
        for s in symbols { result = result.replacingOccurrences(of: s, with: "") }
        
        let cleaned = result.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            
        // Reduce multiple spaces to single space
        return cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
