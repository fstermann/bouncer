import Foundation

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

    /// What a todo's session is kept by: its title, which stays as its tags, dates and box change.
    static func key(of todo: Todo) -> String {
        TaskText(todo.text).title
    }

    /// What Claude is asked: each todo's title, and its note under it.
    static func prompt(for todos: [Todo]) -> String {
        let items = todos.map { todo in
            let note = todo.note.split(separator: "\n").map { "\n  \($0)" }.joined()
            return "- \(TaskText(todo.text).title)\(note)"
        }
        return "Please implement these todos:\n\n" + items.joined(separator: "\n")
    }
}
