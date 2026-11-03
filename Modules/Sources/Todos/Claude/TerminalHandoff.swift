import AppKit

/// Goes on with a chat in the terminal, as `claude --resume` in the folder it began in.
///
/// Opened as a `.command` file handed to Terminal, which asks for no permission the way scripting a
/// terminal would. Handed to Terminal by name, since the default app for `.command` files can be an editor.
enum TerminalHandoff {
    @MainActor
    static func open(session: String, in folder: String) {
        let url = FileManager.default.temporaryDirectory.appending(path: "Bouncer Claude \(session).command")
        do {
            let script = script(shell: ClaudeRun.shell, folder: folder, session: session)
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        } catch {
            return
        }
        let workspace = NSWorkspace.shared
        guard let terminal = workspace.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
        workspace.open([url], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Through the login shell started interactive, like the page's own runs, so a `claude` shell
    /// function applies here too. Without the markers Claude Code leaves for its children, which a
    /// Terminal launched from a Claude Code shell passes on, and which stop the session being saved.
    static func script(shell: String, folder: String, session: String) -> String {
        """
        #!/bin/sh
        unset CLAUDECODE CLAUDE_CODE_CHILD_SESSION
        exec \(quoted(shell)) -lic 'cd "$1" && claude --resume "$2"' claude \(quoted(folder)) \(quoted(session))

        """
    }

    private static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
