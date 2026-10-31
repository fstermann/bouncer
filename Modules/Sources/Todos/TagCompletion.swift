import Foundation

/// Tags in the todo being typed: offered while one is typed after `#`, and added or taken out from
/// the tag menu. Tags live only on a todo's first line; the lines under it are its note.
enum TagCompletion {
    /// The tags matching the `#word` the draft ends in: those starting with it, then those containing
    /// it, then those holding its letters in order. None once the draft has moved past it, or for a
    /// tag already on the todo.
    static func suggestions(for draft: String, from tags: [String]) -> [String] {
        guard !draft.contains("\n"), let word = lastWord(of: draft), word.hasPrefix("#"),
              !word.dropFirst().hasPrefix("#")
        else { return [] }
        let query = word.dropFirst().lowercased()
        let taken = TaskText(String(draft.dropLast(word.count))).tags
        let open = tags.filter { !taken.contains($0) }
        let starting = open.filter { $0.lowercased().hasPrefix(query) }
        let containing = open.filter { !starting.contains($0) && $0.lowercased().contains(query) }
        let loose = open.filter { !starting.contains($0) && !containing.contains($0) && holds(query, in: $0) }
        return starting + containing + loose
    }

    /// `draft` with the `#word` it ends in replaced by `tag`, ready for the next word.
    static func completing(_ draft: String, with tag: String) -> String {
        String(draft.dropLast(lastWord(of: draft)?.count ?? 0)) + "#\(tag) "
    }

    /// `draft` with `tag` added to the end of its first line, or taken out of it.
    static func toggling(_ tag: String, in draft: String) -> String {
        var lines = draft.components(separatedBy: "\n")
        let words = lines[0].split(separator: " ").map(String.init)
        if words.contains("#\(tag)") {
            lines[0] = words.filter { $0 != "#\(tag)" }.joined(separator: " ")
        } else {
            let first = lines[0].trimmingCharacters(in: .whitespaces)
            lines[0] = (first.isEmpty ? "" : first + " ") + "#\(tag) "
        }
        return lines.joined(separator: "\n")
    }

    /// The tags offered for what is typed into a note's tag field, as for `#typed`, leaving out those
    /// it carries.
    static func suggestions(for typed: String, carrying carried: [String], from tags: [String]) -> [String] {
        suggestions(for: "#" + typed.drop { $0 == "#" }, from: tags.filter { !carried.contains($0) })
    }

    /// The tag typed into a note's tag field, without its `#`, or `nil` for none.
    static func tag(from typed: String) -> String? {
        let tag = typed.trimmingCharacters(in: CharacterSet(charactersIn: " ,")).drop { $0 == "#" }
        return tag.isEmpty ? nil : String(tag)
    }

    private static func lastWord(of draft: String) -> String? {
        draft.split(separator: " ", omittingEmptySubsequences: false).last.map(String.init)
    }

    private static func holds(_ query: String, in tag: String) -> Bool {
        var letters = tag.lowercased()[...]
        return query.allSatisfy { letter in
            guard let found = letters.firstIndex(of: letter) else { return false }
            letters = letters[letters.index(after: found)...]
            return true
        }
    }
}
