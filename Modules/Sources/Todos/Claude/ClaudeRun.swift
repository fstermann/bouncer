import Darwin
import Foundation

/// One question to Claude Code, asked by running `claude -p` in a folder, through the user's login
/// shell: that is where `claude` is on their path, and where a shell function wrapping it, such as
/// one picking a config folder by directory, is defined.
@MainActor
final class ClaudeRun {
    private let process = Process()

    /// Runs until Claude has answered or `stop` is called, reporting what it says as it says it.
    ///
    /// - Returns: the shell's exit status, and the last of what it printed as errors, which says why
    ///   when Claude could not be started.
    func ask(
        _ question: String, in folder: String, resuming session: String?, onEvent: (ClaudeEvent) -> Void
    ) async -> (status: Int32, errors: String) {
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(filePath: Self.shell)
        process.arguments = ["-lic", #"cd "$1" && shift && claude "$@""#, "claude", folder]
            + ["-p", "--output-format", "stream-json", "--include-partial-messages", "--verbose"]
            + (session.map { ["--resume", $0] } ?? []) + ["--", question]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = errors
        let exit = AsyncStream<Int32> { continuation in
            process.terminationHandler = { process in
                continuation.yield(process.terminationStatus)
                continuation.finish()
            }
        }
        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        let errorLines = Task {
            var lines: [String] = []
            for try await line in errors.fileHandleForReading.bytes.lines { lines.append(line) }
            return lines
        }
        do {
            for try await line in output.fileHandleForReading.bytes.lines {
                if let event = ClaudeStream.event(from: line) { onEvent(event) }
            }
        } catch {}
        var status: Int32 = -1
        for await code in exit { status = code }
        // An interactive shell without a terminal says it cannot use its line editor.
        let printed = (try? await errorLines.value) ?? []
        return (status, printed.filter { !$0.contains("can't change option: zle") }.suffix(3).joined(separator: "\n"))
    }

    /// An interactive shell ignores SIGTERM, so Claude, its child, is ended first, and then the shell.
    func stop() {
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        let children = Process()
        children.executableURL = URL(filePath: "/usr/bin/pkill")
        children.arguments = ["-TERM", "-P", "\(pid)"]
        try? children.run()
        children.waitUntilExit()
        kill(pid, SIGKILL)
    }

    private static var shell: String {
        guard let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell else { return "/bin/zsh" }
        return String(cString: shell)
    }
}
