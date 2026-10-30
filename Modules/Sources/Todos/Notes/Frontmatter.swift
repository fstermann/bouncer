import Foundation

/// A Markdown file's YAML frontmatter, as Obsidian writes its properties: one `key:` line each, its
/// list items indented under it. Only the scalars and lists Obsidian writes are read; any other
/// property is kept line for line, so a note's own properties survive Bouncer writing it.
struct Frontmatter: Equatable {
    struct Property: Equatable {
        let key: String
        /// The key's line and the lines under it, as they stand in the file.
        var lines: [String]

        var values: [String] {
            let inline = lines[0].dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
            if inline.hasPrefix("["), inline.hasSuffix("]") {
                return inline.dropFirst().dropLast().split(separator: ",").map { Self.unquoted(String($0)) }
                    .filter { !$0.isEmpty }
            }
            if !inline.isEmpty { return [Self.unquoted(inline)] }
            return lines.dropFirst().map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("-") }
                .map { Self.unquoted(String($0.dropFirst())) }
                .filter { !$0.isEmpty }
        }

        var value: String? { values.first }

        init(key: String, lines: [String]) {
            self.key = key
            self.lines = lines
        }

        /// A scalar, or with `isList` a block list, the way Obsidian writes each.
        init(key: String, values: [String], isList: Bool) {
            self.key = key
            lines = isList || values.isEmpty
                ? ["\(key):"] + values.map { "  - \(Self.quoted($0))" }
                : ["\(key): \(Self.quoted(values[0]))"]
        }

        private static func unquoted(_ raw: String) -> String {
            let value = raw.trimmingCharacters(in: .whitespaces)
            guard value.count >= 2, let first = value.first, first == "\"" || first == "'", value.last == first
            else { return value }
            let inner = String(value.dropFirst().dropLast())
            return first == "\"" ? inner.replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\") : inner.replacingOccurrences(of: "''", with: "'")
        }

        /// Plain where YAML reads it back as the same text, double-quoted otherwise.
        private static func quoted(_ value: String) -> String {
            let special = CharacterSet(charactersIn: "[]{},#&*!|>'\"%@`-?:")
            let isPlain = !value.isEmpty && value.trimmingCharacters(in: .whitespaces) == value
                && !value.contains(": ") && !value.contains(" #") && !value.hasSuffix(":")
                && value.unicodeScalars.first.map { !special.contains($0) } == true
            guard !isPlain else { return value }
            let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"" + escaped + "\""
        }
    }

    var properties: [Property]

    /// `markdown` taken apart into its properties and the text after them. Without frontmatter, all
    /// of it is the body.
    static func split(_ markdown: String) -> (frontmatter: Frontmatter, body: String) {
        let lines = markdown.components(separatedBy: "\n")
        guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") else {
            return (Frontmatter(properties: []), markdown)
        }
        var properties: [Property] = []
        for line in lines[1..<end] {
            if let key = key(of: line) {
                properties.append(Property(key: key, lines: [line]))
            } else if !properties.isEmpty {
                properties[properties.count - 1].lines.append(line)
            }
        }
        return (Frontmatter(properties: properties), lines[(end + 1)...].joined(separator: "\n"))
    }

    /// Back as the file's text, with no frontmatter at all while there are no properties.
    func joined(with body: String) -> String {
        guard !properties.isEmpty else { return body }
        return (["---"] + properties.flatMap(\.lines) + ["---"]).joined(separator: "\n") + "\n" + body
    }

    subscript(key: String) -> Property? {
        properties.first { $0.key == key }
    }

    /// Writes `property` where its key stands, or after the others.
    mutating func set(_ property: Property) {
        if let index = properties.firstIndex(where: { $0.key == property.key }) {
            properties[index] = property
        } else {
            properties.append(property)
        }
    }

    /// A key starts a line, unindented, and is not a list item.
    private static func key(of line: String) -> String? {
        guard let first = line.first, !first.isWhitespace, first != "-", first != "#",
              let colon = line.firstIndex(of: ":")
        else { return nil }
        let rest = line[line.index(after: colon)...]
        guard rest.isEmpty || rest.first == " " else { return nil }
        return String(line[..<colon])
    }
}
