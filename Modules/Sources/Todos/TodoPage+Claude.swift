import Settings

extension TodoPage {
    struct OpenGroups {
        let queued: [Todo]
        let working: [Todo]
        let others: [Todo]
    }

    /// Split from one sort of `open`, rather than one sort for each.
    var groups: OpenGroups {
        let open = open
        return OpenGroups(
            queued: open.filter { ClaudeQueue.isForClaude($0) && !$0.isInProgress },
            working: open.filter { ClaudeQueue.isForClaude($0) && $0.isInProgress },
            others: open.filter { !ClaudeQueue.isForClaude($0) }
        )
    }

    /// The todos waiting for Claude, by the repository they go to.
    var queueGroups: [(folder: String, todos: [Todo])] {
        ClaudeQueue.groups(queued.filter { !$0.isDone }, repositories: repositories)
            .map { ($0.folder ?? claudeFolder, $0.todos) }
    }

    /// The todos Claude works on, by the session they were sent to, in the order they are listed.
    /// Those sent before sessions were kept have none, and are left out.
    var workingSessions: [(session: ClaudeSession, todos: [Todo])] {
        var groups: [(session: ClaudeSession, todos: [Todo])] = []
        for todo in working {
            guard let session = sessions[ClaudeQueue.key(of: todo)] else { continue }
            if let index = groups.firstIndex(where: { $0.session == session }) {
                groups[index].todos.append(todo)
            } else {
                groups.append((session, [todo]))
            }
        }
        return groups
    }
}
