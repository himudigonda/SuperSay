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
            let map = ["f i": "fi", "f l": "fl", "f f": "ff", "n t": "nt"]
            for (k, v) in map { result = result.replacingOccurrences(of: k, with: v) }
        }
        
        if options.cleanURLs {
            let regex = try? NSRegularExpression(pattern: "https?://\\S+", options: .caseInsensitive)
            result = regex?.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "[link]") ?? result
        }
        
        if options.cleanHandles {
            result = result.replacingOccurrences(of: "@\\w+", with: "", options: .regularExpression)
        }
        
        if options.expandAbbr {
            let abbr = ["e.g.": "for example", "i.e.": "that is", "etc.": "etcetera"]
            for (k, v) in abbr { result = result.replacingOccurrences(of: k, with: v) }
        }
        
        // Final purification: Remove placeholders and purely symbolic noise
        let symbols = ["\u{FFFC}", "￼", "•", "●", "▪", "◦", "‣", "⁃"]
        for s in symbols { result = result.replacingOccurrences(of: s, with: "") }
        
        return result.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                // Only keep lines that contain at least one letter or number
                line.rangeOfCharacter(from: .alphanumerics) != nil
            }
            .joined(separator: " ")
    }
}
