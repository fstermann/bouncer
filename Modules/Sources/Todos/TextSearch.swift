import Foundation

/// Where a search's text is found in a todo's, whatever its case and accents.
enum TextSearch {
    /// Whether `query` is found anywhere in `text`. Folded once and compared literally: the
    /// comparison that also finds the ranges made searching a long list slow.
    static func contains(_ query: String, in text: String) -> Bool {
        let query = folded(query.trimmingCharacters(in: .whitespaces))
        return !query.isEmpty && folded(text).range(of: query, options: .literal) != nil
    }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    static func ranges(of query: String, in text: String) -> [Range<String.Index>] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        var rest = text.startIndex..<text.endIndex
        while let found = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: rest) {
            ranges.append(found)
            rest = found.upperBound..<text.endIndex
        }
        return ranges
    }
}
