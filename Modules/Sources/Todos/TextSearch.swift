import Foundation

/// Where a search's text is found in a todo's, whatever its case and accents.
enum TextSearch {
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
