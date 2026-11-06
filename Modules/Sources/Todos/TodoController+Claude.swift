import AppKit
import Settings

/// In progress, and sending todos to Claude Code in the repository linked to their tag.
extension TodoController {
    func mark(_ todo: Todo, inProgress: Bool) {
        guard let file, let markdown = file.read(),
              let edited = TodoList.marking(todo, inProgress: inProgress, in: markdown)
        else { return reload() }
        file.write(edited)
        reload()
    }

    /// Starts Claude Code in Terminal on `todos`, and marks them in progress, which moves them to the
    /// group of those Claude works on.
    func send(_ todos: [Todo], to folder: String) {
        let session = ClaudeSession(id: UUID().uuidString.lowercased(), folder: folder)
        TerminalHandoff.start(asking: ClaudeQueue.prompt(for: todos), in: folder, as: session.id)
        for todo in todos { settings.preferences.claudeSessions[ClaudeQueue.key(of: todo)] = session }
        page.sessions = settings.preferences.claudeSessions
        guard let file, var markdown = file.read() else { return }
        for todo in todos {
            markdown = TodoList.marking(todo, inProgress: true, in: markdown) ?? markdown
        }
        file.write(markdown)
        reload()
    }

    func resume(_ todo: Todo) {
        guard let session = settings.preferences.claudeSessions[ClaudeQueue.key(of: todo)] else { return }
        TerminalHandoff.open(session: session.id, in: session.folder)
    }

    /// Ticks `todos` in one write, and forgets their sessions.
    func finish(_ todos: [Todo]) {
        guard let file, var markdown = file.read() else { return }
        let today = TaskDay.string(for: Date())
        for todo in todos {
            markdown = TodoList.toggling(todo, in: markdown, today: today) ?? markdown
            settings.preferences.claudeSessions[ClaudeQueue.key(of: todo)] = nil
        }
        page.sessions = settings.preferences.claudeSessions
        file.write(markdown)
        reload()
    }

    /// The Open dialog would take the page's focus, which closes it; so the page goes, and comes back.
    func link(_ tag: String, links: Bool) async {
        page.menu = nil
        guard links else {
            settings.preferences.tagRepositories[tag] = nil
            page.repositories = settings.preferences.tagRepositories
            return
        }
        let closesOnLeave = closesOnLeave
        await close()
        let dialog = NSOpenPanel()
        dialog.canChooseFiles = false
        dialog.canChooseDirectories = true
        dialog.prompt = "Link"
        dialog.message = "The repository Claude works on #\(tag)'s todos in"
        NSApp.activate(ignoringOtherApps: true)
        if dialog.runModal() == .OK, let url = dialog.url {
            settings.preferences.tagRepositories[tag] = ClaudeChat.trimmed(url.path(percentEncoded: false))
        }
        await open(closesOnLeave: closesOnLeave)
    }
}
