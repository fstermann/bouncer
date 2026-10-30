import Foundation

/// A comma-separated list typed into one field, such as a meeting's people, with names already
/// used offered for the one being typed.
enum ListCompletion {
    static func items(of text: String) -> [String] {
        var seen = Set<String>()
        return text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    static func text(of items: [String]) -> String {
        items.joined(separator: ", ")
    }

    /// The known names starting with the one being typed, then those containing it, leaving out the
    /// names already in the list. None while nothing is being typed.
    static func suggestions(for text: String, from known: [String]) -> [String] {
        let typed = fragment(of: text).lowercased()
        guard !typed.isEmpty else { return [] }
        let taken = Set(items(of: String(text.dropLast(fragment(of: text).count))).map { $0.lowercased() })
        let open = known.filter { !taken.contains($0.lowercased()) && $0.lowercased() != typed }
        let starting = open.filter { $0.lowercased().hasPrefix(typed) }
        let containing = open.filter { !starting.contains($0) && $0.lowercased().contains(typed) }
        return starting + containing
    }

    /// `text` with the name being typed replaced by `item`, ready for the next.
    static func completing(_ typed: String, with item: String) -> String {
        let before = typed.dropLast(fragment(of: typed).count)
        return text(of: items(of: String(before)) + [item]) + ", "
    }

    /// The names in `lists`, the most used first.
    static func known(in lists: [[String]]) -> [String] {
        var counts: [String: Int] = [:]
        lists.joined().forEach { counts[$0, default: 0] += 1 }
        return counts.keys.sorted { (counts[$1] ?? 0, $0) < (counts[$0] ?? 0, $1) }
    }

    /// What follows the last comma.
    private static func fragment(of text: String) -> String {
        let last = text.split(separator: ",", omittingEmptySubsequences: false).last ?? ""
        return String(last.drop { $0 == " " })
    }
}
