import Foundation

/// Images in a todo's or a note's text, embedded the way Obsidian does: `![[Pasted image 20261106143012.png]]`.
enum ImageEmbed {
    /// The name Obsidian gives a pasted image.
    static func name(at date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let stamp = String(
            format: "%04d%02d%02d%02d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
            parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0
        )
        return "Pasted image \(stamp).png"
    }

    static func embed(_ name: String) -> String {
        "![[\(name)]]"
    }

    /// `text` in runs of text and image embeds; `raw` is the embed as written, so it is written back the same.
    enum Segment: Equatable {
        case text(String)
        case image(name: String, raw: String)
    }

    static func segments(of text: String) -> [Segment] {
        var segments: [Segment] = []
        var rest = text[...]
        for match in text.matches(of: pattern) where isImage(String(match.output.1)) {
            let before = rest[..<match.range.lowerBound]
            if !before.isEmpty { segments.append(.text(String(before))) }
            segments.append(.image(name: String(match.output.1), raw: String(match.output.0)))
            rest = text[match.range.upperBound...]
        }
        if !rest.isEmpty { segments.append(.text(String(rest))) }
        return segments
    }

    /// The images embedded in `text`, in order, each once. An embed of a note rather than an image is left out.
    static func names(in text: String) -> [String] {
        var names: [String] = []
        for match in text.matches(of: pattern) {
            let name = String(match.output.1)
            if isImage(name), !names.contains(name) { names.append(name) }
        }
        return names
    }

    /// `text` without its image embeds, for showing beside them.
    static func stripped(_ text: String) -> String {
        let lines = text.replacing(pattern) { isImage(String($0.output.1)) ? "" : String($0.output.0) }
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.split(separator: " ").joined(separator: " ") }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `text` with each image embed whose name is in `paths` swapped for its path.
    static func replacing(in text: String, with paths: [String: String]) -> String {
        text.replacing(pattern) { match in
            let name = String(match.output.1)
            return isImage(name) ? paths[name] ?? String(match.output.0) : String(match.output.0)
        }
    }

    private static func isImage(_ name: String) -> Bool {
        let ext = name.split(separator: ".").last.map { $0.lowercased() } ?? ""
        return name.contains(".") && extensions.contains(ext)
    }

    private static let extensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tif", "tiff", "bmp"]
    /// `![[name]]`, or `![[name|300]]` with Obsidian's width.
    nonisolated(unsafe) private static let pattern = #/!\[\[([^\]|]+)(?:\|[^\]]*)?\]\]/#
}
