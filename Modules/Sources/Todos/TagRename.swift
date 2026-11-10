import Foundation

/// A tag renamed everywhere it is written: on todos, among the categories, in the colours, the chip
/// order and the linked repositories, and on notes. The tags nested under it move with it.
enum TagRename {
    /// `tag` as it reads after `old` is renamed to `new`, or as it was if it is not `old` or under it.
    static func renamed(_ tag: String, from old: String, to new: String) -> String {
        TagPath.matches(tag, old) ? new + tag.dropFirst(old.count) : tag
    }

    /// The name typed, without the `#` and spaces it may carry, or `nil` if it cannot be a tag.
    static func cleaned(_ name: String) -> String? {
        let name = name.trimmingCharacters(in: CharacterSet(charactersIn: " #"))
        guard !name.isEmpty, !name.contains(" "), !name.hasPrefix("/"), !name.hasSuffix("/") else { return nil }
        return name
    }

    /// The todo file with `old` renamed on every task line, in the categories and in the colours.
    static func renaming(_ old: String, to new: String, in markdown: String) -> String {
        var lines = TodoList.lines(of: markdown)
        for todo in TodoList.parse(markdown) where todo.tags.contains(where: { TagPath.matches($0, old) }) {
            lines[todo.line] = lines[todo.line].split(separator: " ", omittingEmptySubsequences: false)
                .map { word in
                    let isTag = word.count > 1 && word.hasPrefix("#") && !word.dropFirst().hasPrefix("#")
                    return isTag ? "#" + renamed(String(word.dropFirst()), from: old, to: new) : String(word)
                }
                .joined(separator: " ")
        }
        var renamed = lines.joined(separator: "\n")
        for category in Categories.parse(renamed) where TagPath.matches(category, old) {
            renamed = Categories.adding(
                Self.renamed(category, from: old, to: new), to: Categories.removing(category, from: renamed)
            )
        }
        if let colors = FileTagColors.parse(renamed), colors.keys.contains(where: { TagPath.matches($0, old) }) {
            renamed = FileTagColors.setting(keys(of: colors, from: old, to: new), in: renamed)
        }
        return renamed
    }

    /// `values` with every key that is `old` or under it renamed. Where a key is renamed onto one
    /// already there, the renamed one's value wins.
    static func keys(of values: [String: String], from old: String, to new: String) -> [String: String] {
        var result = values.filter { !TagPath.matches($0.key, old) }
        for (key, value) in values where TagPath.matches(key, old) {
            result[renamed(key, from: old, to: new)] = value
        }
        return result
    }

    /// The chip order with `old` and the tags under it renamed, each kept once where it first stood.
    static func order(_ order: [String], from old: String, to new: String) -> [String] {
        var seen = Set<String>()
        return order.map { renamed($0, from: old, to: new) }.filter { seen.insert($0).inserted }
    }

    /// A note's tags with `old` renamed, each kept once, or `nil` if none of them was `old` or under it.
    static func noteTags(_ tags: [String], from old: String, to new: String) -> [String]? {
        guard tags.contains(where: { TagPath.matches($0, old) }) else { return nil }
        var seen = Set<String>()
        return tags.map { renamed($0, from: old, to: new) }.filter { seen.insert($0).inserted }
    }
}
