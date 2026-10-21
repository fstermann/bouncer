import BouncerFoundation
import Foundation

/// The Markdown file the todo page reads and writes, and the watch on it while the page is open.
///
/// Found through a security-scoped bookmark made when the user picked it. Picking a file is
/// consent to read it, so a file in a protected folder such as Documents needs no prompt.
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
