import BouncerFoundation
import Foundation

/// A conversation started from the page, kept so it can be picked up again.
///
/// Its turns are Bouncer's own copy: Claude Code's transcript sits in a config folder a shell function
/// can choose by directory, which Bouncer cannot see. Turns added after a hand-off to Terminal stay
/// in Claude Code's transcript only.
struct ClaudeChat: Codable, Identifiable, Equatable {
    /// Claude Code's session ID, empty until the first answer reports it.
    var id: String
    /// Where the session was started, which `--resume` has to run in.
    var folder: String
    var title: String
    var updated: Date
    var exchanges: [ClaudeExchange]

    /// The name the session is given in Claude Code, so `claude --resume` lists it as Bouncer's.
    var sessionName: String { "Bouncer · \(title)" }

    /// The first line of the first question, cut short.
    static func title(for question: String) -> String {
        let line = question.split(whereSeparator: \.isNewline).first.map(String.init) ?? question
        return line.count > 80 ? String(line.prefix(79)) + "…" : line
    }

    /// The folders `chats` began in, most recent first, once each and without `besides`.
    static func folders(of chats: [ClaudeChat], besides: String) -> [String] {
        var seen: Set = [trimmed(besides)]
        return chats.sorted { $0.updated > $1.updated }.map { trimmed($0.folder) }.filter { seen.insert($0).inserted }
    }

    /// The folder written without a trailing slash, which a home folder path comes with.
    static func trimmed(_ folder: String) -> String {
        folder.count > 1 && folder.hasSuffix("/") ? String(folder.dropLast()) : folder
    }
}

/// The chats on disk, one JSON file each in Bouncer's Application Support folder, read when the page
/// opens and written when an answer ends.
enum ClaudeChats {
    static let shown = 50

    static func all() -> [ClaudeChat] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        let chats = files.filter { $0.pathExtension == "json" }.compactMap { url in
            (try? Data(contentsOf: url)).flatMap { try? decoder.decode(ClaudeChat.self, from: $0) }
        }
        return Array(chats.sorted { $0.updated > $1.updated }.prefix(shown))
    }

    static func save(_ chat: ClaudeChat) {
        guard !chat.id.isEmpty else { return }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONEncoder().encode(chat).write(to: folder.appending(path: "\(chat.id).json"), options: .atomic)
        } catch {
            Log.todos.error("Saving a Claude chat failed: \(error, privacy: .public)")
        }
    }

    /// Dev builds get their own, by bundle ID.
    private static var folder: URL {
        URL.applicationSupportDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "com.bouncer.app", directoryHint: .isDirectory)
            .appending(path: "Claude Chats", directoryHint: .isDirectory)
    }
}
