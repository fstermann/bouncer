import Foundation

/// The preset categories, kept as a `categories` list in the todo file's frontmatter, which
/// Obsidian shows and edits as a property. A category is a tag: filtering by one shows the todos
/// tagged with it, and adding one under a filter tags it.
///
/// Only that one key is read or written; the rest of the frontmatter is left as it was.
public enum Categories {
    public static func parse(_ markdown: String) -> [String] {
        guard let block = frontmatter(of: TodoList.lines(of: markdown)) else { return [] }
        let lines = TodoList.lines(of: markdown)
        guard let key = lines[block].firstIndex(where: { $0.hasPrefix("categories:") }) else { return [] }
        let inline = lines[key].dropFirst("categories:".count).trimmingCharacters(in: .whitespaces)
        if inline.hasPrefix("[") {
            return inline.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                .split(separator: ",").map(clean).filter { !$0.isEmpty }
        }
        return listItems(after: key, in: lines, before: block.upperBound)
            .map { clean(lines[$0].drop { $0 != "-" }.dropFirst()) }
    }

    /// `markdown` with `name` added to its categories, creating the list, and the frontmatter
    /// around it, if there is none yet.
    public static func adding(_ name: String, to markdown: String) -> String {
        let name = clean(Substring(name))
        guard !name.isEmpty, !parse(markdown).contains(name) else { return markdown }
        var lines = TodoList.lines(of: markdown)
        guard let block = frontmatter(of: lines) else {
            return "---\ncategories:\n  - \(name)\n---\n" + markdown
        }
        guard let key = lines[block].firstIndex(where: { $0.hasPrefix("categories:") }) else {
            lines.insert(contentsOf: ["categories:", "  - \(name)"], at: block.upperBound)
            return lines.joined(separator: "\n")
        }
        let inline = lines[key].dropFirst("categories:".count).trimmingCharacters(in: .whitespaces)
        if inline.hasPrefix("[") {
            let existing = inline.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
            lines[key] = "categories: [\(existing.isEmpty ? name : existing + ", " + name)]"
        } else {
            let last = listItems(after: key, in: lines, before: block.upperBound).last ?? key
            lines.insert("  - \(name)", at: last + 1)
        }
        return lines.joined(separator: "\n")
    }

    /// The lines between the opening `---` and the closing one, if the file starts with frontmatter.
    private static func frontmatter(of lines: [String]) -> Range<Int>? {
        guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") else { return nil }
        return 1..<end
    }

    private static func listItems(after key: Int, in lines: [String], before end: Int) -> [Int] {
        Array((key + 1)..<end).prefix { lines[$0].trimmingCharacters(in: .whitespaces).hasPrefix("- ") }
    }

    private static func clean(_ value: Substring) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: " \"'#"))
    }
}
