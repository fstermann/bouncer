import BouncerFoundation
import Foundation

/// The Markdown file the todo page reads and writes, and the watch on it while the page is open.
///
/// Either a local file Bouncer keeps itself, or one the user picked, found through a
/// security-scoped bookmark made when they picked it. Picking a file is consent to read it, so a
/// file in a protected folder such as Documents needs no prompt.
@MainActor
final class TodoFile {
    private let url: URL
    private var watch: DispatchSourceFileSystemObject?

    /// - Returns: `nil` when the bookmark no longer leads anywhere. `refreshed` is a new bookmark
    ///   to store when the old one is stale.
    static func resolve(_ bookmark: Data) -> (file: TodoFile, refreshed: Data?)? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &isStale
        ) else { return nil }
        return (TodoFile(url: url), isStale ? try? Self.bookmark(for: url) : nil)
    }

    /// The file in Bouncer's Application Support folder used while no file is picked, created
    /// empty on first use so there is a file to watch. Debug builds get their own, by bundle ID.
    static func local() -> TodoFile? {
        let folder = URL.applicationSupportDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "com.bouncer.app", directoryHint: .isDirectory)
        let url = folder.appending(path: "Todos.md")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) { try Data().write(to: url) }
        } catch {
            Log.todos.error("Creating the local todo file failed: \(error, privacy: .public)")
            return nil
        }
        return TodoFile(url: url)
    }

    static func bookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: .withSecurityScope)
    }

    private init(url: URL) {
        self.url = url
    }

    func read() -> String? {
        access { try? String(contentsOf: url, encoding: .utf8) }
    }

    /// Written in place rather than atomically, so the file keeps its identity and the watch on it,
    /// and Obsidian sees an edit rather than a file replaced.
    func write(_ markdown: String) {
        access {
            do {
                try markdown.write(to: url, atomically: false, encoding: .utf8)
            } catch {
                Log.todos.error("Writing the todo file failed: \(error, privacy: .public)")
            }
        }
    }

    /// Calls `onChange` whenever the file changes on disk, until `stopWatching`.
    ///
    /// A sync client may replace the file rather than edit it, which leaves the watch on a file
    /// that is gone; the watch follows the name onto the new one.
    func watch(onChange: @MainActor @escaping () -> Void) {
        stopWatching()
        let opened = access { open(url.path, O_EVTONLY) }
        guard opened >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: opened, eventMask: [.write, .extend, .delete, .rename], queue: .main
        )
        source.setEventHandler { [weak self, unowned source] in
            MainActor.assumeIsolated {
                if !source.data.isDisjoint(with: [.delete, .rename]) { self?.watch(onChange: onChange) }
                onChange()
            }
        }
        source.setCancelHandler { close(opened) }
        source.resume()
        watch = source
    }

    func stopWatching() {
        watch?.cancel()
        watch = nil
    }

    private func access<T>(_ body: () -> T) -> T {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return body()
    }
}
