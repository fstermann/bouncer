import Foundation

/// One checkbox line in the todo file.
public struct Todo: Hashable, Sendable, Identifiable {
    /// Its line in the file, which is also what identifies it until the file next changes.
    public let line: Int
    /// Everything after the checkbox, tags and dates included.
    public let text: String
    public let isDone: Bool
    /// The indented lines under it, which Obsidian shows as part of the task.
    public var note = ""

    public var id: Int { line }
}

/// The todo file's checkboxes, read and edited as Markdown task lines (`- [ ] text`), the format
/// Obsidian writes. Everything else in the file is left exactly as it was.
///
/// Pure over strings, so it is tested without a file.
public enum TodoList {
    public static func parse(_ markdown: String) -> [Todo] {
        let lines = lines(of: markdown)
        return lines.enumerated().compactMap { index, line in
            task(in: line).map {
                Todo(line: index, text: $0.text, isDone: $0.isDone, note: note(under: index, in: lines))
            }
        }
    }

    /// `markdown` with `todo` ticked or unticked, or `nil` when its line no longer holds it: the
    /// file changed underneath, and editing by line number would hit some other line.
    ///
    /// Ticking stamps the day it was done, `✅ 2026-10-21`, the way the Tasks plugin does, so a todo
    /// ticked here counts in the vault's queries about what was done when.
    public static func toggling(_ todo: Todo, in markdown: String, today: String) -> String? {
        var lines = lines(of: markdown)
        guard holds(todo, lines),
              let box = lines[todo.line].range(of: todo.isDone ? "[x]" : "[ ]", options: .caseInsensitive)
        else { return nil }
        var line = lines[todo.line].replacingCharacters(in: box, with: todo.isDone ? "[ ]" : "[x]")
        if todo.isDone {
            line = line.replacing(/\s*✅ \d{4}-\d{2}-\d{2}/, with: "")
        } else if !line.contains("✅") {
            line += " ✅ \(today)"
        }
        lines[todo.line] = line
        return lines.joined(separator: "\n")
    }

    /// `markdown` with `todo` rewritten to `text` and its note to `note`, or `nil` when its line no
    /// longer holds it. Its checkbox and indentation stay as they were.
    public static func replacing(_ todo: Todo, with text: String, note: String, in markdown: String) -> String? {
        var lines = lines(of: markdown)
        guard holds(todo, lines), let box = lines[todo.line].firstMatch(of: /[-*+] \[[ xX]\][ ]/) else { return nil }
        let line = lines[todo.line]
        let indent = String(line.prefix { $0 == " " || $0 == "\t" }) + "    "
        let written = note.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { indent + $0 }
        let old = todo.line...(todo.line + noteLines(under: todo.line, in: lines).count)
        lines.replaceSubrange(old, with: [String(line[..<box.range.upperBound]) + text] + written)
        return lines.joined(separator: "\n")
    }

    /// `markdown` without `todos` and their notes. A todo whose line no longer holds it stays.
    public static func removing(_ todos: some Collection<Todo>, from markdown: String) -> String {
        var lines = lines(of: markdown)
        // Bottom up, so taking one out leaves the lines of those above where they were.
        for todo in todos.sorted(by: { $0.line > $1.line }) where holds(todo, lines) {
            lines.removeSubrange(todo.line...(todo.line + noteLines(under: todo.line, in: lines).count))
        }
        return lines.joined(separator: "\n")
    }

    /// `markdown` with an open todo added at its end. Lines after the first become its note.
    public static func appending(_ text: String, to markdown: String) -> String {
        let lines = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let first = lines.first else { return markdown }
        let separator = markdown.isEmpty || markdown.hasSuffix("\n") ? "" : "\n"
        let note = lines.dropFirst().map { "    \($0)\n" }.joined()
        return markdown + separator + "- [ ] \(first)\n" + note
    }

    /// A todo's text from what was typed, due on `due`.
    public static func task(from draft: String, due: String?) -> String {
        var lines = draft.components(separatedBy: "\n")
        guard var first = lines.first?.trimmingCharacters(in: .whitespaces), !first.isEmpty else { return draft }
        if let due { first += " 📅 \(due)" }
        lines[0] = first
        return lines.joined(separator: "\n")
    }

    static func lines(of markdown: String) -> [String] {
        markdown.components(separatedBy: "\n")
    }

    /// Whether `todo`'s line still holds it: after the file changed, editing by line number would
    /// hit some other line.
    private static func holds(_ todo: Todo, _ lines: [String]) -> Bool {
        guard lines.indices.contains(todo.line), let current = task(in: lines[todo.line]) else { return false }
        return current.text == todo.text && current.isDone == todo.isDone
    }

    private static func note(under index: Int, in lines: [String]) -> String {
        noteLines(under: index, in: lines).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
    }

    /// The lines indented under the task on line `index`, up to the first that is not: a blank
    /// line, a line back at the task's depth, or a subtask of its own.
    private static func noteLines(under index: Int, in lines: [String]) -> ArraySlice<String> {
        let depth = indentation(of: lines[index])
        return lines[(index + 1)...].prefix { line in
            !line.trimmingCharacters(in: .whitespaces).isEmpty && indentation(of: line) > depth
                && task(in: line) == nil
        }
    }

    private static func indentation(of line: String) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
    }

    private static func task(in line: String) -> (text: String, isDone: Bool)? {
        guard let match = line.wholeMatch(of: /\s*[-*+] \[([ xX])\] (.*)/) else { return nil }
        return (String(match.2).trimmingCharacters(in: .whitespaces), match.1 != " ")
    }
}
