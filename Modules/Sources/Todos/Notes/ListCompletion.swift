import Foundation

/// The names typed into a meeting's people or project field, with the ones already used offered for
/// the one being typed.
enum ListCompletion {
    /// The known names starting with what is typed, then those containing it, leaving out the ones
    /// chosen; all the others while nothing is typed.
    static func suggestions(for typed: String, carrying chosen: [String], from known: [String]) -> [String] {
        let typed = typed.trimmingCharacters(in: .whitespaces).lowercased()
        let taken = Set(chosen.map { $0.lowercased() })
        let open = known.filter { !taken.contains($0.lowercased()) }
        guard !typed.isEmpty else { return open }
        let starting = open.filter { $0.lowercased().hasPrefix(typed) }
        let containing = open.filter { !starting.contains($0) && $0.lowercased().contains(typed) }
        return starting + containing
    }

    /// The name typed, or `nil` for none.
    static func name(from typed: String) -> String? {
        typed.trimmingCharacters(in: CharacterSet(charactersIn: " ,")).nilIfEmpty
    }

    /// The names in `lists`, the most used first.
    static func known(in lists: [[String]]) -> [String] {
        var counts: [String: Int] = [:]
        lists.joined().forEach { counts[$0, default: 0] += 1 }
        return counts.keys.sorted { (counts[$1] ?? 0, $0) < (counts[$0] ?? 0, $1) }
    }
}
