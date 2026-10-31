import BouncerFoundation
import Foundation

/// The folder meeting notes are kept in, one Markdown file each, and the watch on it while the
/// notes page is open.
///
/// Either a local folder Bouncer keeps itself, or one the user picked, such as a meetings folder in
/// an Obsidian vault, found through a security-scoped bookmark made when they picked it. Every
/// Markdown file in it or the folders under it, one per project, is a note, so picking a vault's root
/// lists the whole vault. Hidden folders, such as the vault's settings, are passed over.
@MainActor
final class NoteFolder {
    private let url: URL
    private var watch: DispatchSourceFileSystemObject?

    /// - Returns: `nil` when the bookmark no longer leads anywhere. `refreshed` is a new bookmark
    ///   to store when the old one is stale.
    static func resolve(_ bookmark: Data) -> (folder: NoteFolder, refreshed: Data?)? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &isStale
        ) else { return nil }
        return (NoteFolder(url: url), isStale ? try? TodoFile.bookmark(for: url) : nil)
    }

    /// The folder in Bouncer's Application Support folder used while none is picked, created on
    /// first use. Debug builds get their own, by bundle ID.
    static func local() -> NoteFolder? {
        let url = URL.applicationSupportDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "com.bouncer.app", directoryHint: .isDirectory)
            .appending(path: "Notes", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            Log.todos.error("Creating the local notes folder failed: \(error, privacy: .public)")
            return nil
        }
        return NoteFolder(url: url)
    }

    private init(url: URL) {
        self.url = url
    }

    /// Every Markdown file in the folder and its projects' folders, read whole: the page searches the
    /// notes' text too.
    func notes() -> [Note] {
        access {
            let files = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )?.allObjects as? [URL] ?? []
            // The files come with the links on the way to the folder resolved, so its path is compared resolved too.
            let depth = url.resolvingSymlinksInPath().pathComponents.count
            return files.filter { $0.pathExtension.lowercased() == "md" }.compactMap { file in
                guard let markdown = try? String(contentsOf: file, encoding: .utf8) else { return nil }
                let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                let name = file.resolvingSymlinksInPath().pathComponents.dropFirst(depth).joined(separator: "/")
                return Note(name: name, markdown: markdown, modified: modified)
            }
        }
    }

    func read(_ name: String) -> String? {
        access { try? String(contentsOf: file(name), encoding: .utf8) }
    }

    /// Written in place rather than atomically, so Obsidian sees an edit rather than a file replaced.
    func write(_ markdown: String, to name: String) {
        access {
            do {
                try markdown.write(to: file(name), atomically: false, encoding: .utf8)
            } catch {
                Log.todos.error("Writing a note failed: \(error, privacy: .public)")
            }
        }
    }

    /// A name for a new file, `name` itself while no file has it, numbered after it otherwise.
    func free(_ name: String, besides current: String? = nil) -> String {
        access {
            let base = String(name.dropLast(3))
            var candidate = name
            var number = 2
            while candidate != current, FileManager.default.fileExists(atPath: file(candidate).path) {
                candidate = "\(base) \(number).md"
                number += 1
            }
            return candidate
        }
    }

    /// Renames `name` to `wanted`, or a free name like it, moving it into another project's folder if
    /// `wanted` is in one; returns the name the file ends up with.
    func rename(_ name: String, to wanted: String) -> String {
        guard name != wanted else { return name }
        let target = free(wanted, besides: name)
        guard target != name else { return name }
        return access {
            do {
                try FileManager.default.createDirectory(
                    at: file(target).deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try FileManager.default.moveItem(at: file(name), to: file(target))
                return target
            } catch {
                Log.todos.error("Renaming a note failed: \(error, privacy: .public)")
                return name
            }
        }
    }

    /// To the Trash, where Finder can put it back.
    func trash(_ name: String) {
        access {
            do {
                try FileManager.default.trashItem(at: file(name), resultingItemURL: nil)
            } catch {
                Log.todos.error("Moving a note to the Trash failed: \(error, privacy: .public)")
            }
        }
    }

    /// Calls `onChange` whenever a file in the folder is added, removed or renamed, until
    /// `stopWatching`. An edit inside a file is read on the next open.
    func watch(onChange: @MainActor @escaping () -> Void) {
        stopWatching()
        let opened = access { open(url.path, O_EVTONLY) }
        guard opened >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: opened, eventMask: [.write], queue: .main
        )
        source.setEventHandler { MainActor.assumeIsolated(onChange) }
        source.setCancelHandler { close(opened) }
        source.resume()
        watch = source
    }

    func stopWatching() {
        watch?.cancel()
        watch = nil
    }

    private func file(_ name: String) -> URL {
        url.appending(path: name, directoryHint: .notDirectory)
    }

    private func access<T>(_ body: () -> T) -> T {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return body()
    }
}
