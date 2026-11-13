import Foundation
import Settings

/// Todos tagged `#claude`, waiting to be sent to Claude Code in a repository, and those it was sent.
enum ClaudeQueue {
    static let tag = "claude"

    static func isForClaude(_ todo: Todo) -> Bool {
        todo.tags.contains(tag)
    }

    /// The repository linked to the most specific of `todo`'s tags, `#work/bouncer` before `#work`.
    static func repository(of todo: Todo, in repositories: [String: String]) -> String? {
        for tag in todo.tags where tag != Self.tag {
            if let found = TagPath.lineage(of: tag).reversed().lazy.compactMap({ repositories[$0] }).first {
                return found
            }
        }
        return nil
    }

    /// `todos` by the repository each is sent to, `nil` for those with no linked tag, in the order the
    /// repositories first come up.
    static func groups(_ todos: [Todo], repositories: [String: String]) -> [(folder: String?, todos: [Todo])] {
        var groups: [(folder: String?, todos: [Todo])] = []
        for todo in todos {
            let folder = repository(of: todo, in: repositories)
            if let index = groups.firstIndex(where: { $0.folder == folder }) {
                groups[index].todos.append(todo)
            } else {
                groups.append((folder, [todo]))
            }
        }
        return groups
    }

    /// Where Claude Code keeps `session`'s transcript, which is never written if its terminal closed
    /// before Claude started. Claude Code names a folder's directory by its path, every character
    /// other than a letter or digit a dash.
    static func transcript(of session: ClaudeSession, home: String) -> String {
        let directory = String(session.folder.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
        return "\(trimmed(home))/.claude/projects/\(directory)/\(session.id).jsonl"
    }

    private static func trimmed(_ path: String) -> String {
        path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    /// What a todo's session is kept by: its title, which stays as its tags, dates and box change.
    static func key(of todo: Todo) -> String {
        TaskText(todo.text).title
    }

    /// What Claude is asked: each todo's title, and its note under it, with each image embed swapped for the
    /// path in `images` it was copied to; then the branch to work on, and to ask how to commit first.
    static func prompt(for todos: [Todo], images: [String: String] = [:], branch: String) -> String {
        let items = todos.map { todo in
            let note = todo.note.split(separator: "\n")
                .map { "\n  \(ImageEmbed.replacing(in: String($0), with: images))" }
            return "- \(ImageEmbed.replacing(in: TaskText(todo.text).title, with: images))\(note.joined())"
        }
        return "Please implement these todos:\n\n" + items.joined(separator: "\n") + "\n\n"
            + "Work on a new branch named \(branch). Before changing anything, use the AskUserQuestion tool to "
            + "ask whether to make one commit per todo or group them, and whether to open a pull request."
    }

    /// Stamped to the minute, so it does not clash with the branches of earlier sends.
    static func branch(at date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(
            format: "todos/%04d%02d%02d-%02d%02d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0
        )
    }

    /// The images embedded in `todos`' titles and notes, each once.
    static func imageNames(in todos: [Todo]) -> [String] {
        ImageEmbed.names(in: todos.map { TaskText($0.text).title + "\n" + $0.note }.joined(separator: "\n"))
    }
}
