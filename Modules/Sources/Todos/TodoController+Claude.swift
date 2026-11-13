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
        let prompt = ClaudeQueue.prompt(
            for: todos, images: copiedImages(of: todos, for: session.id), branch: ClaudeQueue.branch(at: Date())
        )
        TerminalHandoff.start(asking: prompt, in: folder, as: session.id)
        for todo in todos { settings.preferences.claudeSessions[ClaudeQueue.key(of: todo)] = session }
        page.sessions = settings.preferences.claudeSessions
        guard let file, var markdown = file.read() else { return }
        for todo in todos {
            markdown = TodoList.marking(todo, inProgress: true, in: markdown) ?? markdown
        }
        file.write(markdown)
        reload()
    }

    /// Copies of the todos' images by name, in a temporary folder: Terminal may not read the images folder,
    /// which macOS guards when it is in Documents, and Bouncer reaches only through its bookmark.
    private func copiedImages(of todos: [Todo], for session: String) -> [String: String] {
        let names = ClaudeQueue.imageNames(in: todos)
        guard !names.isEmpty, let store = ImageStore.current(in: settings) else { return [:] }
        let destination = FileManager.default.temporaryDirectory.appending(path: "Bouncer Claude \(session)")
        var paths: [String: String] = [:]
        for name in names {
            paths[name] = store.copy(name, into: destination)?.path(percentEncoded: false)
        }
        return paths
    }

    /// Sends the session's todos again when Claude Code never saved it, as nothing could resume it.
    func resume(_ todo: Todo) {
        let sessions = settings.preferences.claudeSessions
        guard let session = sessions[ClaudeQueue.key(of: todo)] else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        guard !FileManager.default.fileExists(atPath: ClaudeQueue.transcript(of: session, home: home)) else {
            return TerminalHandoff.open(session: session.id, in: session.folder)
        }
        send(page.working.filter { sessions[ClaudeQueue.key(of: $0)] == session }, to: session.folder)
    }

    /// Puts `todos` back in the queue to be sent again, and forgets their sessions. Their terminal stays open.
    func abort(_ todos: [Todo]) {
        guard let file, var markdown = file.read() else { return }
        for todo in todos {
            markdown = TodoList.marking(todo, inProgress: false, in: markdown) ?? markdown
            settings.preferences.claudeSessions[ClaudeQueue.key(of: todo)] = nil
        }
        page.sessions = settings.preferences.claudeSessions
        file.write(markdown)
        reload()
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
