import Foundation

/// The block structure of an answer, which SwiftUI's Markdown leaves out: it draws inline syntax only.
/// Inline syntax stays in each block's text, for `AttributedString` to draw.
enum MarkdownBlock: Equatable {
    case heading(String)
    case paragraph(String)
    /// A list item: `•` or its number, and how many levels deep it is nested.
    case item(marker: String, text: String, depth: Int)
    case quote(String)
    case code(String)
    /// Rows of cells, the header first.
    case table([[String]])
    case rule

    static func parse(_ text: String) -> [MarkdownBlock] {
        var parser = Parser()
        for line in text.components(separatedBy: "\n") { parser.take(line) }
        return parser.finish()
    }

    /// Lines are taken one at a time, since a paragraph, a fence or a table runs over several.
    private struct Parser {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var code: [String]?
        var table: [String] = []

        mutating func take(_ line: String) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if let lines = code {
                    blocks.append(.code(lines.joined(separator: "\n")))
                    code = nil
                } else {
                    flush()
                    code = []
                }
            } else if code != nil {
                code?.append(line)
            } else if trimmed.hasPrefix("|") {
                if !paragraph.isEmpty { flush() }
                table.append(trimmed)
            } else {
                if !table.isEmpty { flush() }
                takeText(line, trimmed: trimmed)
            }
        }

        private mutating func takeText(_ line: String, trimmed: String) {
            if trimmed.isEmpty {
                flush()
            } else if let block = MarkdownBlock.titled(trimmed) ?? MarkdownBlock.single(line, trimmed: trimmed) {
                flush()
                blocks.append(block)
            } else if paragraph.isEmpty, case .item(let marker, let text, let depth) = blocks.last,
                      line.hasPrefix("  ") {
                // A wrapped item's next line, indented under it.
                blocks[blocks.count - 1] = .item(marker: marker, text: text + "\n" + trimmed, depth: depth)
            } else {
                paragraph.append(trimmed)
            }
        }

        mutating func finish() -> [MarkdownBlock] {
            if let lines = code { blocks.append(.code(lines.joined(separator: "\n"))) }
            flush()
            return blocks
        }

        private mutating func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))) }
            if !table.isEmpty { blocks.append(MarkdownBlock.table(from: table)) }
            paragraph = []
            table = []
        }
    }

    /// Cells split at pipes, the `|---|` row under the header left out. Without that row it is no
    /// table, so it is kept as written.
    private static func table(from lines: [String]) -> MarkdownBlock {
        let rows = lines.map { line in
            line.trimmingCharacters(in: CharacterSet(charactersIn: "| "))
                .components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }
        let isRule = { (row: [String]) in row.allSatisfy { !$0.isEmpty && $0.allSatisfy { "-:".contains($0) } } }
        guard rows.count > 1, isRule(rows[1]) else { return .code(lines.joined(separator: "\n")) }
        return .table([rows[0]] + rows.dropFirst(2))
    }

    /// A rule, list item or quote, each a line of its own.
    private static func single(_ line: String, trimmed: String) -> MarkdownBlock? {
        if ["---", "***", "___"].contains(trimmed) { return .rule }
        if let item = item(line) { return item }
        if trimmed.hasPrefix(">") { return .quote(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    private static func titled(_ line: String) -> MarkdownBlock? {
        let hashes = line.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count), line.dropFirst(hashes.count).first == " " else { return nil }
        return .heading(String(line.dropFirst(hashes.count + 1)))
    }

    private static func item(_ line: String) -> MarkdownBlock? {
        let indent = line.prefix { $0 == " " }.count
        let rest = line.dropFirst(indent)
        let depth = indent / 2
        if let first = rest.first, "-*+".contains(first), rest.dropFirst().first == " " {
            return .item(marker: "•", text: String(rest.dropFirst(2)), depth: depth)
        }
        let digits = rest.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count < 4 else { return nil }
        let after = rest.dropFirst(digits.count)
        guard let dot = after.first, dot == "." || dot == ")", after.dropFirst().first == " " else { return nil }
        return .item(marker: digits + ".", text: String(after.dropFirst(2)), depth: depth)
    }
}
