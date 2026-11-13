import AppKit
import BouncerFoundation
import Settings
import SwiftUI

/// Opens and closes the todo page, and keeps it in step with the file behind it.
///
/// Nothing runs while the page is closed: the file is read when it opens and watched only until it
/// closes. A change synced in from another device while it is closed is simply read on the next open.
@MainActor
@Observable
public final class TodoController {
    /// Switches the notch panel to another page.
    public var onSwitchPage: (@MainActor (NotchPage) -> Void)? {
        get { panel.pageButton.onPick }
        set { panel.pageButton.onPick = newValue }
    }
    /// The pages that are on, offered right of the notch.
    public var pages: [NotchPage] {
        get { panel.pageButton.pages }
        set { panel.pageButton.pages = newValue }
    }
    public private(set) var isOpen = false
    /// Pressing ⌘⇧B anywhere. The shortcut is registered only while this is set.
    public var onShortcut: (@MainActor () -> Void)? {
        didSet {
            shortcut?.unregister()
            shortcut = onShortcut.flatMap { action in HotKey(.todos, action: action) }
        }
    }

    let settings: SettingsStore
    let page = TodoPage()
    private let panel = PagePanel<TodoPage>()
    var file: TodoFile?
    /// How long the panel takes to grow, or `nil` while animation is off. Read once per open, so it
    /// leaves the way it arrived.
    private var duration: TimeInterval?
    /// The wait before each just-ticked todo leaves the list.
    private var lingerings: [Todo: Task<Void, Never>] = [:]
    /// The wait before the todos being deleted leave the file, all at once.
    private var deletion: Task<Void, Never>?
    private var shortcut: HotKey?
    /// Off for a page opened from the keyboard, with the pointer anywhere: only Escape or a click
    /// elsewhere closes that one.
    var closesOnLeave = true

    /// Long enough to see a mis-click and take it back.
    private static let linger: Duration = .seconds(3)

    public init(settings: SettingsStore) {
        self.settings = settings
        panel.pageButton.current = .todos
        page.onToggle = { [weak self] todo in self?.toggle(todo) }
        page.onAdd = { [weak self] text in self?.add(text) }
        page.onEdit = { [weak self] todo, text, note in self?.edit(todo, to: text, note: note) }
        page.onDelete = { [weak self] todo in self?.delete(todo) }
        page.onMark = { [weak self] todo, inProgress in self?.mark(todo, inProgress: inProgress) }
        page.onSend = { [weak self] todos, folder in self?.send(todos, to: folder) }
        page.onResume = { [weak self] todo in self?.resume(todo) }
        page.onFinish = { [weak self] todos in self?.finish(todos) }
        page.onAbort = { [weak self] todos in self?.abort(todos) }
        page.onLink = { [weak self] tag, links in Task { await self?.link(tag, links: links) } }
        page.onRestore = { [weak self] todo in self?.restore(todo) }
        page.onAddCategory = { [weak self] name in self?.addCategory(name) }
        page.onRemoveCategory = { [weak self] name in self?.removeCategory(name) }
        page.onResize = { [weak self] in self.map { $0.panel.fit($0.page) } }
        page.onColor = { [weak self] tag, color in self?.setColor(color, of: tag) }
        page.onRename = { [weak self] old, new in self?.rename(old, to: new) }
        page.onOrder = { [weak self] order in self?.settings.preferences.tagOrder = order }
        panel.mayCloseOnLeave = { [weak self] in self.map { $0.closesOnLeave && $0.page.isIdle } ?? true }
        panel.onDismiss = { [weak self] in Task { await self?.close() } }
        // Closes a menu the way a popover goes, spending the click; tag suggestions leave the field
        // clickable.
        panel.onClickOutsideMenu = { [weak self] in
            guard let page = self?.page, let menu = page.menu, menu.kind != .suggestions else { return false }
            page.menu = nil
            return true
        }
        panel.onFind = { [weak self] in withAnimation(.snappy) { self?.page.openSearch() } }
        // Out of a row's menu, a category being named, an edit or the search first, and only then out
        // of the page.
        panel.onEscape = { [weak self] in
            guard let self else { return }
            if page.menu != nil {
                page.menu = nil
            } else if page.isAddingCategory {
                page.isAddingCategory = false
            } else if let editing = page.editing {
                page.editing = nil
                lingerAfterEditing(editing)
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
    /// `onceCovered` then takes away underneath it.
    ///
    /// - Parameters:
    ///   - screen: whose notch to open from, the one under the pointer when `nil`.
    ///   - start: in AppKit screen coordinates.
    public func open(
        on screen: NSScreen? = nil, from start: CGRect? = nil, closesOnLeave: Bool = true,
        onceCovered: @MainActor () async -> Void = {}
    ) async {
        guard !isOpen, let file = resolveFile() else { return }
        isOpen = true
        self.closesOnLeave = closesOnLeave
        self.file = file
        page.tagOrder = settings.preferences.tagOrder
        page.repositories = settings.preferences.tagRepositories
        page.sessions = settings.preferences.claudeSessions
        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        page.claudeFolder = ClaudeChat.trimmed(settings.preferences.claudeFolder ?? home)
        page.images = ImageStore.current(in: settings)?.pastedImages
        reload()
        file.watch { [weak self] in self?.reload() }
        duration = settings.preferences.animateBar ? settings.preferences.barAnimationDuration : nil
        await panel.open(page, on: screen, over: duration, from: start, onceCovered: onceCovered)
    }

    /// Takes the page back into the notch, or, given `items`, into the panel `items` brings up
    /// underneath it, which hands the page its frame through `Shaping` before it shows; without
    /// `animated`, at once.
    public func close(animated: Bool = true, into items: ((@escaping Shaping) async -> Void)? = nil) async {
        guard isOpen else { return }
        isOpen = false
        lingerings.values.forEach { $0.cancel() }
        lingerings = [:]
        page.lingering = []
        deleteNow()
        page.saveEdit()
        page.editing = nil
        page.menu = nil
        page.closeSearch()
        file?.stopWatching()
        file = nil
        await panel.close(over: animated ? duration : nil, into: items)
    }

    /// The panel's frame while it is open, in AppKit screen coordinates: what the next page grows
    /// out of when switched to.
    public var panelFrame: CGRect? { panel.frame }

    private func resolveFile() -> TodoFile? {
        Self.resolvedFile(in: settings)
    }

    /// The picked file, or the local one while none is picked.
    static func resolvedFile(in settings: SettingsStore) -> TodoFile? {
        guard let bookmark = settings.preferences.todoFile else { return TodoFile.local() }
        guard let resolved = TodoFile.resolve(bookmark) else {
            Log.todos.error("Todo file: the bookmark no longer resolves")
            return nil
        }
        if let refreshed = resolved.refreshed { settings.preferences.todoFile = refreshed }
        return resolved.file
    }

    func reload() {
        let markdown = file?.read() ?? ""
        page.todos = TodoList.parse(markdown)
        page.categories = Categories.parse(markdown)
        // The file's colours, once it keeps any; until then the ones set on this device, which the
        // first colour set writes to it. Kept in the preferences too, for the notes page.
        let colors = FileTagColors.parse(markdown)
        page.tagColors = colors ?? settings.preferences.tagColors
        if let colors {
            let merged = settings.preferences.tagColors.merging(colors) { $1 }
            if merged != settings.preferences.tagColors { settings.preferences.tagColors = merged }
        }
    }

    /// The page has taken the colour already; every colour it shows goes to the file.
    private func setColor(_ color: String?, of tag: String) {
        settings.preferences.tagColors[tag] = color
        guard let file else { return }
        file.write(FileTagColors.setting(page.tagColors, in: file.read() ?? ""))
        reload()
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
            withAnimation(.snappy) { _ = page.lingering.remove(todo) }
        }
    }

    private func add(_ text: String) {
        guard let file else { return }
        let task = TodoList.task(from: text, due: page.draftDue, time: page.draftTime)
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
            self?.deleteAnimated()
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
        remove(todos)
    }

    /// Takes the rows out before their lines: rows are known by their line, which removing lines shifts.
    private func deleteAnimated() {
        deletion = nil
        let todos = page.deleting
        withAnimation(.snappy) {
            page.todos.removeAll(where: todos.contains)
        } completion: { [weak self] in
            guard let self else { return }
            page.deleting.subtract(todos)
            remove(todos)
        }
    }

    private func remove(_ todos: Set<Todo>) {
        guard !todos.isEmpty, let file, let markdown = file.read() else { return }
        file.write(TodoList.removing(todos, from: markdown))
        reload()
    }

    private func addCategory(_ name: String) {
        guard let file else { return }
        file.write(Categories.adding(name, to: file.read() ?? ""))
        reload()
    }

    private func rename(_ old: String, to new: String) {
        TagRenamer.rename(old, to: new, settings: settings)
        page.filters = Set(page.filters.map { TagRename.renamed($0, from: old, to: new) })
        page.tagOrder = settings.preferences.tagOrder
        page.repositories = settings.preferences.tagRepositories
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

    /// The file used while none is picked, for showing in Settings.
    public static var localFileURL: URL { TodoFile.localURL }

    /// Where a stored bookmark leads, for showing in Settings.
    public static func url(of bookmark: Data) -> URL? {
        var isStale = false
        return try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &isStale)
    }
}
