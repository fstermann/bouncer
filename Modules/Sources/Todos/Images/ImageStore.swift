import AppKit
import BouncerFoundation
import Settings

/// The folder pasted images are saved in, shared by todos and notes: the one picked in Settings, or
/// `assets` beside the todo file, where Obsidian is usually set to keep attachments.
@MainActor
struct ImageStore {
    let folder: URL
    /// What the folder was reached through, whose security scope is opened to read or write in it.
    private let scope: URL

    /// Resolved again each time, so a folder picked in Settings counts at once.
    static func current(in settings: SettingsStore) -> ImageStore? {
        if let bookmark = settings.preferences.imagesFolder {
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &isStale
            ) else {
                Log.todos.error("Images folder: the bookmark no longer resolves")
                return nil
            }
            if isStale, let refreshed = try? TodoFile.bookmark(for: url) {
                settings.preferences.imagesFolder = refreshed
            }
            return ImageStore(folder: url, scope: url)
        }
        let todos = settings.preferences.todoFile.flatMap(TodoController.url(of:)) ?? TodoFile.localURL
        return ImageStore(folder: todos.deletingLastPathComponent().appending(path: "assets"), scope: todos)
    }

    /// Saves `png` under a new name and returns the embed for it.
    func save(_ png: Data) -> String? {
        saveFile(png).map { ImageEmbed.embed($0.lastPathComponent) }
    }

    /// Saves `png` under a new name and returns where.
    func saveFile(_ png: Data) -> URL? {
        access {
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let file = folder.appending(path: freeName(ImageEmbed.name(at: Date())))
                try png.write(to: file)
                return file
            } catch {
                Log.todos.error("Saving a pasted image failed: \(error, privacy: .public)")
                return nil
            }
        }
    }

    func image(named name: String) -> NSImage? {
        access { NSImage(contentsOf: folder.appending(path: name)) }
    }

    var pastedImages: PastedImages {
        PastedImages(save: save, load: image(named:))
    }

    private func freeName(_ name: String) -> String {
        let base = String(name.dropLast(4))
        var candidate = name
        var number = 2
        while FileManager.default.fileExists(atPath: folder.appending(path: candidate).path) {
            candidate = "\(base) \(number).png"
            number += 1
        }
        return candidate
    }

    private func access<T>(_ body: () -> T) -> T {
        let scoped = scope.startAccessingSecurityScopedResource()
        defer { if scoped { scope.stopAccessingSecurityScopedResource() } }
        return body()
    }
}

/// Saving a pasted image and reading one back, for the views.
struct PastedImages {
    /// Returns the embed to type for the saved image.
    let save: @MainActor (Data) -> String?
    let load: @MainActor (String) -> NSImage?
}
