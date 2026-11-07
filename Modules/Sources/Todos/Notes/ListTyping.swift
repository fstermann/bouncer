import Foundation

/// Markdown lists as they are typed into a note: Return on a list item starts the next one, Return on
/// an empty one ends the list, and Tab and Shift-Tab nest an item deeper or bring it back out.
enum ListTyping {
    struct Edit: Equatable {
        /// What is rewritten, in UTF-16 offsets as `NSTextView` counts them.
        var range: NSRange
        var replacement: String
        /// Where the cursor goes after.
        var caret: Int
    }

    /// One level of nesting, as Obsidian writes it by default.
    static let indent = "\t"

    /// The edit Return makes at `caret`, `nil` outside a list item, where Return is a plain new line.
    static func newline(at caret: NSRange, in text: String) -> Edit? {
        guard caret.length == 0 else { return nil }
        let text = text as NSString
        let line = lineRange(at: caret.location, in: text)
        guard let item = Item(text.substring(with: line)) else { return nil }
        // Before the marker's end, Return splits nothing of the item; a plain new line does that.
        guard caret.location >= line.location + item.prefix.utf16.count else { return nil }
        if item.isEmpty {
            return Edit(range: line, replacement: item.indent, caret: line.location + item.indent.utf16.count)
        }
        let next = "\n" + item.indent + item.nextMarker
        return Edit(range: caret, replacement: next, caret: caret.location + next.utf16.count)
    }

    /// The edit Tab (`deeper`) or Shift-Tab makes on the list item the caret is in, `nil` outside one.
    /// A numbered item nested deeper starts its own list at 1.
    static func indenting(at caret: NSRange, in text: String, deeper: Bool) -> Edit? {
        let text = text as NSString
        let line = lineRange(at: caret.location, in: text)
        guard let item = Item(text.substring(with: line)) else { return nil }
        var indent = item.indent
        if deeper {
            indent += Self.indent
        } else if indent.hasSuffix(Self.indent) {
            indent.removeLast(Self.indent.count)
        } else if indent.hasPrefix("    ") {
            indent.removeFirst(4)
        } else if !indent.isEmpty {
            indent = ""
        } else {
            return nil
        }
        let marker = deeper && item.number != nil ? item.marker.replacing(/^\d+/, with: "1") : item.marker
        let old = (item.indent + item.marker) as NSString
        let new = indent + marker
        let shift = new.utf16.count - old.length
        return Edit(
            range: NSRange(location: line.location, length: old.length), replacement: new,
            caret: max(line.location + new.utf16.count, caret.location + shift)
        )
    }

    /// The line holding `location`, without its line break.
    private static func lineRange(at location: Int, in text: NSString) -> NSRange {
        var start = 0, end = 0, contentsEnd = 0
        text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
        return NSRange(location: start, length: contentsEnd - start)
    }

    /// A list item's line: its indentation, its marker with the space after it, and what follows.
    private struct Item {
        let indent: String
        /// `- `, `* `, `+ `, `1. ` or `1) `, with `[ ] ` after it for a task.
        let marker: String
        let content: String
        let number: Int?

        init?(_ line: String) {
            let pattern = /([ \t]*)([-*+]|(\d{1,9})[.)])( \[[ xX\/]\])? (.*)/
            guard let match = line.wholeMatch(of: pattern) else { return nil }
            indent = String(match.1)
            marker = String(match.2) + String(match.4 ?? "") + " "
            content = String(match.5)
            number = match.3.flatMap { Int($0) }
        }

        var prefix: String { indent + marker }
        var isEmpty: Bool { content.trimmingCharacters(in: .whitespaces).isEmpty }

        /// The same kind of marker, counted on, and an open box for a task, whether this one is ticked.
        var nextMarker: String {
            var marker = marker.replacing(/\[[xX\/]\]/, with: "[ ]")
            if let number { marker = marker.replacing(/^\d+/, with: String(number + 1)) }
            return marker
        }
    }
}
