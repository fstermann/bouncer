import BouncerFoundation
import Foundation
import Settings

/// Opens and closes the todo page, and keeps it in step with the file behind it.
///
/// Nothing runs while the page is closed: the file is read when it opens and watched only until it
/// closes. A change synced in from another device while it is closed is simply read on the next open.
@MainActor
public final class TodoController {
    /// Switches the notch panel to the hidden items. `nil` hides the switch.
    public var onSwitchPage: (@MainActor () -> Void)?
    public private(set) var isOpen = false
    /// Pressing ⌘⇧B anywhere. The shortcut is registered only while this is set.
    public var onShortcut: (@MainActor () -> Void)? {
        didSet {
            shortcut?.unregister()
            shortcut = onShortcut.flatMap { action in TodoShortcut(action: action) }
        }
    }

    private let settings: SettingsStore
    private let page = TodoPage()
    private let panel = TodoPanel()
    private var file: TodoFile?
    /// How long the panel takes to grow, or `nil` while animation is off. Read once per open, so it
    /// leaves the way it arrived.
    private var duration: TimeInterval?
    /// The wait before each just-ticked todo leaves the list.
    private var lingerings: [Todo: Task<Void, Never>] = [:]
    /// The wait before the todos being deleted leave the file, all at once.
    private var deletion: Task<Void, Never>?
    private var shortcut: TodoShortcut?
    /// Off for a page opened from the keyboard, with the pointer anywhere: only Escape or a click
    /// elsewhere closes that one.
    private var closesOnLeave = true

    /// Long enough to see a mis-click and take it back.
    private static let linger: Duration = .seconds(3)

    public init(settings: SettingsStore) {
        self.settings = settings
        page.onToggle = { [weak self] todo in self?.toggle(todo) }
        page.onAdd = { [weak self] text in self?.add(text) }
        page.onEdit = { [weak self] todo, text, note in self?.edit(todo, to: text, note: note) }
        page.onDelete = { [weak self] todo in self?.delete(todo) }
        page.onRestore = { [weak self] todo in self?.restore(todo) }
        page.onAddCategory = { [weak self] name in self?.addCategory(name) }
        page.onRemoveCategory = { [weak self] name in self?.removeCategory(name) }
        page.onSwitch = { [weak self] in self?.onSwitchPage?() }
        page.onResize = { [weak self] in self.map { $0.panel.fit($0.page) } }
        page.onColor = { [weak self] tag, color in self?.settings.preferences.tagColors[tag] = color }
        panel.mayCloseOnLeave = { [weak self] in self.map { $0.closesOnLeave && $0.page.isIdle } ?? true }
        panel.onDismiss = { [weak self] in Task { await self?.close() } }
        // Closes a menu the way a popover goes, spending the click; tag suggestions leave the field
        // clickable.
        panel.onClickOutsideMenu = { [weak self] in
            guard let page = self?.page, let menu = page.menu, menu.kind != .suggestions else { return false }
            page.menu = nil
            return true
        }
        // Out of a row's menu, a category being named or an edit first, and only then out of the page.
        panel.onEscape = { [weak self] in
            guard let self else { return }
            if page.menu != nil {
                page.menu = nil
            } else if page.isAddingCategory {
                page.isAddingCategory = false
            } else if let editing = page.editing {
                page.editing = nil
                lingerAfterEditing(editing)
            } else {
                Task { await self.close() }
            }
        }
    }

    public func toggle() async {
        isOpen ? await close() : await open()
    }

    /// Grows the page out of the notch, or, given `start`, out of the panel already there, which
    /// `onceCovered` then takes away underneath it.
    ///
    /// - Parameter start: in AppKit screen coordinates.
    public func open(
        from start: CGRect? = nil, closesOnLeave: Bool = true, onceCovered: @MainActor () async -> Void = {}
    ) async {
        guard !isOpen, let file = resolveFile() else { return }
        isOpen = true
        self.closesOnLeave = closesOnLeave
        self.file = file
        page.showsSwitch = onSwitchPage != nil
        page.tagColors = settings.preferences.tagColors
        reload()
        file.watch { [weak self] in self?.reload() }
        duration = settings.preferences.animateBar ? settings.preferences.barAnimationDuration : nil
        await panel.open(page, over: duration, from: start, onceCovered: onceCovered)
    }

    /// Takes the page back into the notch, or, given `items`, into the panel `items` brings up
    /// underneath it, which hands the page its frame through `Shaping` before it shows.
    public func close(into items: ((@escaping Shaping) async -> Void)? = nil) async {
        guard isOpen else { return }
        isOpen = false
        lingerings.values.forEach { $0.cancel() }
        lingerings = [:]
        page.lingering = []
        deleteNow()
        page.saveEdit()
        page.editing = nil
        page.menu = nil
        file?.stopWatching()
        file = nil
        await panel.close(over: duration, into: items)
    }

    /// The picked file, or the local one while none is picked.
    private func resolveFile() -> TodoFile? {
        guard let bookmark = settings.preferences.todoFile else { return TodoFile.local() }
        guard let resolved = TodoFile.resolve(bookmark) else {
            Log.todos.error("Todo file: the bookmark no longer resolves")
            return nil
        }
        if let refreshed = resolved.refreshed { settings.preferences.todoFile = refreshed }
        return resolved.file
    }

    private func reload() {
        let markdown = file?.read() ?? ""
        page.todos = TodoList.parse(markdown)
        page.categories = Categories.parse(markdown)
    }

    /// Edits the file as it is now, not as it was read: a sync may have changed it since.
    private func toggle(_ todo: Todo) {
        let today = TaskDay.string(for: Date())
        guard let file, let markdown = file.read(),
              let edited = TodoList.toggling(todo, in: markdown, today: today)
        else { return reload() }
        file.write(edited)
        lingerings.removeValue(forKey: todo)?.cancel()
        page.lingering.remove(todo)
        reload()
        // Found again in the file, since ticking changed its text.
        if !todo.isDone, let ticked = page.todos.first(where: { $0.line == todo.line && $0.isDone }) {
            linger(ticked)
        }
    }

    /// Keeps a just-ticked todo in the list for a moment, then lets it go.
    private func linger(_ todo: Todo) {
        page.lingering.insert(todo)
        lingerings[todo] = Task { [weak self] in
            try? await Task.sleep(for: Self.linger)
            guard let self, !Task.isCancelled else { return }
            lingerings[todo] = nil
            page.lingering.remove(todo)
        }
    }

    private func add(_ text: String) {
        guard let file else { return }
        let task = TodoList.task(from: text, due: page.draftDue)
        file.write(TodoList.appending(task, to: file.read() ?? ""))
        reload()
    }

    private func edit(_ todo: Todo, to text: String, note: String) {
        guard let file, let markdown = file.read(),
              let edited = TodoList.replacing(todo, with: text, note: note, in: markdown)
        else { return reload() }
        file.write(edited)
        reload()
        if let saved = page.todos.first(where: { $0.line == todo.line && $0.isDone }) {
            lingerings.removeValue(forKey: todo)?.cancel()
            page.lingering.remove(todo)
            lingerAfterEditing(saved)
        }
    }

    /// Keeps a done todo listed a moment after it was changed, so a mistake can be put right; it
    /// would otherwise leave the list at once.
    private func lingerAfterEditing(_ todo: Todo) {
        guard todo.isDone, !page.showsDone else { return }
        lingerings.removeValue(forKey: todo)?.cancel()
        linger(todo)
    }

    /// Marks `todo` as deleted for a moment, so a mis-click can be taken back, before it leaves the file.
    private func delete(_ todo: Todo) {
        page.deleting.insert(todo)
        deletion?.cancel()
        deletion = Task { [weak self] in
            try? await Task.sleep(for: Self.linger)
            guard !Task.isCancelled else { return }
            self?.deleteNow()
        }
    }

    private func restore(_ todo: Todo) {
        page.deleting.remove(todo)
        if page.deleting.isEmpty { deletion?.cancel() }
    }

    private func deleteNow() {
        deletion?.cancel()
        deletion = nil
        let todos = page.deleting
        page.deleting = []
        guard !todos.isEmpty, let file, let markdown = file.read() else { return }
        file.write(TodoList.removing(todos, from: markdown))
        reload()
    }

    private func addCategory(_ name: String) {
        guard let file else { return }
        file.write(Categories.adding(name, to: file.read() ?? ""))
        reload()
    }

    private func removeCategory(_ name: String) {
        guard let file, let markdown = file.read() else { return }
        file.write(Categories.removing(name, from: markdown))
        reload()
    }
}

extension TodoController {
    /// A bookmark to `url`, to store as `Preferences.todoFile`.
    public static func bookmark(for url: URL) -> Data? {
        do {
            return try TodoFile.bookmark(for: url)
        } catch {
            Log.todos.error("Bookmarking the todo file failed: \(error, privacy: .public)")
            return nil
        }
    }

    /// Where a stored bookmark leads, for showing in Settings.
    public static func url(of bookmark: Data) -> URL? {
        var isStale = false
        return try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &isStale)
    }
}
