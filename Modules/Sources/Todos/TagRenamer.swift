import Settings

/// Writes a tag's new name to the todo file, the notes and the preferences, whichever page it was
/// renamed from: the two pages share their tags.
@MainActor
enum TagRenamer {
    static func rename(_ old: String, to new: String, settings: SettingsStore) {
        guard old != new else { return }
        if settings.preferences.enableTodos, let file = TodoController.resolvedFile(in: settings),
           let markdown = file.read() {
            let renamed = TagRename.renaming(old, to: new, in: markdown)
            if renamed != markdown { file.write(renamed) }
        }
        if settings.preferences.enableNotes, let folder = NoteController.resolvedFolder(in: settings) {
            for var note in folder.notes() {
                guard let tags = TagRename.noteTags(note.tags, from: old, to: new) else { continue }
                note.tags = tags
                folder.write(note.markdown(over: folder.read(note.name) ?? ""), to: note.name)
            }
        }
        settings.preferences.tagColors = TagRename.keys(of: settings.preferences.tagColors, from: old, to: new)
        settings.preferences.tagRepositories = TagRename.keys(
            of: settings.preferences.tagRepositories, from: old, to: new
        )
        settings.preferences.tagOrder = TagRename.order(settings.preferences.tagOrder, from: old, to: new)
    }
}
