import AppKit
import BouncerFoundation
import Settings
import SwiftUI

/// Opens and closes the notes page, and keeps it and any note popped out of it in step with the
/// folder behind them.
///
/// Nothing runs while the page is closed: the folder is read when the page opens and watched only
/// until it closes. A note being written is saved a moment after each change,
/// and at once when it is left.
@MainActor
public final class NoteController {
    /// Switches the notch panel to another page.
    public var onSwitchPage: (@MainActor (NotchPage) -> Void)?
    /// The other pages, offered at the top right while they are on.
    public var pageSwitches: [NotchPage] = []
    public private(set) var isOpen = false
    /// Pressing ⌘⇧N anywhere. The shortcut is registered only while this is set.
    public var onShortcut: (@MainActor () -> Void)? {
        didSet {
            shortcut?.unregister()
            shortcut = onShortcut.flatMap { action in HotKey(.notes, action: action) }
        }
    }

    private let settings: SettingsStore
    private let page = NotePage()
    private let panel = PagePanel<NotePage>()
    private var folder: NoteFolder?
    private var duration: TimeInterval?
    private var shortcut: HotKey?
    private var closesOnLeave = true
    private var windows: [NoteWindow] = []
    /// The wait before the latest change to each note open is written.
    private var saves: [ObjectIdentifier: Task<Void, Never>] = [:]

    private static let saveDelay: Duration = .milliseconds(600)

    public init(settings: SettingsStore) {
        self.settings = settings
        page.onCreate = { [weak self] title in self?.create(title) }
        page.onOpen = { [weak self] note in self?.openNote(note) }
        page.onBack = { [weak self] in self?.back() }
        page.onEdit = { [weak self] draft in self?.scheduleSave(draft) }
        page.onDelete = { [weak self] note in self?.delete(note) }
        page.onPopOut = { [weak self] in self?.popOut() }
        page.onSwitch = { [weak self] target in self?.onSwitchPage?(target) }
        page.onResize = { [weak self] in self.map { $0.panel.fit($0.page) } }
        page.onColor = { [weak self] tag, color in self?.settings.preferences.tagColors[tag] = color }
        page.onOrder = { [weak self] order in self?.settings.preferences.tagOrder = order }
        panel.mayCloseOnLeave = { [weak self] in self.map { $0.closesOnLeave && $0.page.isIdle } ?? true }
        panel.onDismiss = { [weak self] in Task { await self?.close() } }
        panel.onClickOutsideMenu = { [weak self] in
            guard let page = self?.page, page.menu != nil else { return false }
            page.menu = nil
            return true
        }
        panel.onFind = { [weak self] in
            guard let page = self?.page, page.editing == nil else { return }
            withAnimation(.snappy) { page.openSearch() }
        }
        panel.onEscape = { [weak self] in
            guard let self else { return }
            if page.menu != nil {
                page.menu = nil
            } else if page.editing != nil {
                back()
            } else if page.isSearching {
                withAnimation(.snappy) { page.closeSearch() }
            } else {
                Task { await self.close() }
            }
        }
    }

    public func toggle() async {
        isOpen ? await close() : await open()
    }

    /// Grows the page out of the notch, or, given `start`, out of the panel already there, which
    /// `onceCovered` then takes away underneath it. A note left open in it is open again.
    public func open(
        on screen: NSScreen? = nil, from start: CGRect? = nil, closesOnLeave: Bool = true,
        onceCovered: @MainActor () async -> Void = {}
    ) async {
        guard !isOpen, let folder = resolveFolder() else { return }
        isOpen = true
        self.closesOnLeave = closesOnLeave
        self.folder = folder
        page.switches = pageSwitches
        page.tagColors = settings.preferences.tagColors
        page.tagOrder = settings.preferences.tagOrder
        page.now = Date()
        reload()
        if let draft = page.editing, let note = page.notes.first(where: { $0.name == draft.saved.name }) {
            page.editing = NoteDraft(note)
        } else {
            page.editing = nil
        }
        folder.watch { [weak self] in self?.reload() }
        duration = settings.preferences.animateBar ? settings.preferences.barAnimationDuration : nil
        await panel.open(page, on: screen, over: duration, from: start, onceCovered: onceCovered)
    }

    /// Takes the page back into the notch, or, given `items`, into the panel `items` brings up
    /// underneath it; without `animated`, at once.
    public func close(animated: Bool = true, into items: ((@escaping Shaping) async -> Void)? = nil) async {
        guard isOpen else { return }
        isOpen = false
        page.menu = nil
        page.closeSearch()
        if let draft = page.editing { finish(draft) }
        folder?.stopWatching()
        // Kept for the notes popped out, which are still being saved to it.
        if windows.isEmpty { folder = nil }
        await panel.close(over: animated ? duration : nil, into: items)
    }

    /// The panel's frame while it is open, in AppKit screen coordinates: what the next page grows
    /// out of when switched to.
    public var panelFrame: CGRect? { panel.frame }

    private func resolveFolder() -> NoteFolder? {
        if let folder { return folder }
        guard let bookmark = settings.preferences.notesFolder else { return NoteFolder.local() }
        guard let resolved = NoteFolder.resolve(bookmark) else {
            Log.todos.error("Notes folder: the bookmark no longer resolves")
            return nil
        }
        if let refreshed = resolved.refreshed { settings.preferences.notesFolder = refreshed }
        return resolved.folder
    }

    private func reload() {
        page.notes = folder?.notes() ?? []
    }

    /// Starts a meeting now, tagged with the filters, and opens it with the cursor in its text.
    private func create(_ title: String) {
        guard let folder else { return }
        let start = NoteEditor.minute(of: Date())
        var note = Note(
            name: "", title: title, start: start, tags: page.lackingFilters(in: []), body: Note.template
        )
        note.name = folder.free(NoteName.make(title: title, start: start))
        folder.write(note.markdown(over: ""), to: note.name)
        reload()
        page.editing = NoteDraft(note)
    }

    /// Opens `note` in the panel, or brings forward the window it is popped out into.
    private func openNote(_ note: Note) {
        if let window = windows.first(where: { $0.draft.saved.name == note.name }) {
            window.makeKeyAndOrderFront(nil)
            return
        }
        page.editing = NoteDraft(note)
    }

    private func back() {
        guard let draft = page.editing else { return }
        finish(draft)
        page.editing = nil
        reload()
        page.focusRequests += 1
    }

    private func scheduleSave(_ draft: NoteDraft) {
        saves[draft.id]?.cancel()
        saves[draft.id] = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled else { return }
            self?.save(draft)
        }
    }

    /// Writes the note over the file as it is now, keeping whatever properties it has of its own.
    private func save(_ draft: NoteDraft) {
        saves.removeValue(forKey: draft.id)?.cancel()
        guard let folder, draft.note != draft.saved else { return }
        let note = draft.note
        folder.write(note.markdown(over: folder.read(note.name) ?? ""), to: note.name)
        draft.saved = note
    }

    /// Saves the note, renames its file once its title or start has changed, and moves it into its
    /// project's folder: not while it is typed, when every letter would rename it.
    private func finish(_ draft: NoteDraft) {
        save(draft)
        let note = draft.saved
        let isMisplaced = NoteName.folder(of: note.name) != NoteName.folder(for: note.project)
        guard let folder, isMisplaced || note.title != draft.opened.title || note.start != draft.opened.start
        else { return }
        draft.saved.name = folder.rename(
            note.name, to: NoteName.make(title: note.title, start: note.start, project: note.project)
        )
    }

    private func delete(_ note: Note) {
        if let draft = page.editing, draft.saved.name == note.name {
            saves.removeValue(forKey: draft.id)?.cancel()
            page.editing = nil
            page.focusRequests += 1
        }
        folder?.trash(note.name)
        reload()
    }

    /// Moves the note open in the panel into a window of its own, and puts the panel away.
    private func popOut() {
        guard let draft = page.editing else { return }
        save(draft)
        page.editing = nil
        let window = NoteWindow(
            draft: draft, known: NoteSuggestions(page),
            onEdit: { [weak self] in self?.scheduleSave($0) },
            onDelete: { [weak self] in self?.deletePoppedOut(draft) }
        )
        window.onClose = { [weak self] in self?.closed($0) }
        windows.append(window)
        if window.frame.origin == .zero { window.center() }
        Task { await close() }
        window.makeKeyAndOrderFront(nil)
    }

    private func deletePoppedOut(_ draft: NoteDraft) {
        guard let window = windows.first(where: { $0.draft === draft }) else { return }
        saves.removeValue(forKey: draft.id)?.cancel()
        windows.removeAll { $0 === window }
        window.onClose = nil
        window.close()
        folder?.trash(draft.saved.name)
        if isOpen { reload() } else if windows.isEmpty { folder = nil }
    }

    private func closed(_ window: NoteWindow) {
        finish(window.draft)
        windows.removeAll { $0 === window }
        if isOpen {
            reload()
        } else if windows.isEmpty {
            folder = nil
        }
    }
}

extension NoteController {
    /// A bookmark to `url`, to store as `Preferences.notesFolder`.
    public static func bookmark(for url: URL) -> Data? {
        TodoController.bookmark(for: url)
    }

    /// Where a stored bookmark leads, for showing in Settings.
    public static func url(of bookmark: Data) -> URL? {
        TodoController.url(of: bookmark)
    }
}
