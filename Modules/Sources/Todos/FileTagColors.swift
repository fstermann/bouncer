import Foundation

/// The tags' colours, kept in the todo file's frontmatter as a `tag-colors` map, so they travel with
/// the file to every device it syncs to. Obsidian keeps a property it cannot edit as it is.
enum FileTagColors {
    static let key = "tag-colors"

    /// Tag to colour name, or `nil` while the file keeps none.
    static func parse(_ markdown: String) -> [String: String]? {
        guard let property = Frontmatter.split(markdown).frontmatter[key] else { return nil }
        var colors: [String: String] = [:]
        for line in property.lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1).map(clean)
            if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty { colors[parts[0]] = parts[1] }
        }
        return colors
    }

    /// `markdown` keeping `colors`, by tag, in place of those it kept; the rest of it as it was.
    static func setting(_ colors: [String: String], in markdown: String) -> String {
        var (frontmatter, body) = Frontmatter.split(markdown)
        let entries = colors.sorted { $0.key < $1.key }.map { "  \($0.key): \($0.value)" }
        frontmatter.set(Frontmatter.Property(key: key, lines: ["\(key):"] + entries))
        return frontmatter.joined(with: body)
    }

    private static func clean(_ part: Substring) -> String {
        part.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
    }
}
