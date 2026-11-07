import AppKit
import Settings

/// Brings up timed todos, meetings about to start and Claude's answers as a tab beside the notch,
/// which opens their page when clicked.
///
/// Nothing polls. The todo file and the notes folder are watched while their pages are on, and
/// between changes there is one wait, for the next reminder to start or stop showing.
@MainActor
public final class ReminderController {
    /// A reminder clicked: its page to open, and the note a meeting's reminder is for.
    public var onOpen: (@MainActor (NotchPage, String?) -> Void)?

    private let settings: SettingsStore
    private var todos: [Reminder] = []
    private var meetings: [Reminder] = []
    private var answers: [Reminder] = []
    /// Kept for the session only: a reminder brought back by a restart is one worth seeing again.
    private var dismissed: Set<String> = []
    private var todoFile: TodoFile?
    private var noteFolder: NoteFolder?
    private var wait: Task<Void, Never>?
    private var tab: ReminderTabWindow?

    public init(settings: SettingsStore) {
        self.settings = settings
    }

    /// The sources last followed, so a preference change elsewhere does not restart the watches.
    private var followed: Sources?

    private struct Sources: Equatable {
        let todos: Bool
        let notes: Bool
        let file: Data?
        let folder: Data?
    }

    /// Watches the todo file and the notes folder for whichever of the two pages is on, and lets go of
    /// the other, once either is switched or another file or folder picked.
    public func follow(_ preferences: Preferences) {
        let sources = Sources(
            todos: preferences.enableTodos, notes: preferences.enableNotes,
            file: preferences.todoFile, folder: preferences.notesFolder
        )
        guard sources != followed else { return }
        followed = sources
        follow(todos: sources.todos, notes: sources.notes)
    }

    private func follow(todos: Bool, notes: Bool) {
        todoFile?.stopWatching()
        todoFile = todos ? TodoController.resolvedFile(in: settings) : nil
        todoFile?.watch { [weak self] in self?.readTodos() }
        readTodos()
        noteFolder?.stopWatching()
        noteFolder = notes ? NoteController.resolvedFolder(in: settings) : nil
        noteFolder?.watch { [weak self] in self?.readMeetings() }
        readMeetings()
    }

    /// Claude has answered in `chat`, which shows unless its page is open.
    public func claudeAnswered(_ chat: String) {
        answers.removeAll()
        answers.append(.claude(chat: chat, at: Date()))
        update()
    }

    /// The page is open, so its reminders are seen: Claude's go; the others stay until dismissed, as
    /// the page may be open for something else.
    public func seen(_ page: NotchPage) {
        guard page == .claude, !answers.isEmpty else { return }
        answers.removeAll()
        update()
    }

    func dismiss(_ reminder: Reminder) {
        dismissed.insert(reminder.id)
        answers.removeAll { $0.id == reminder.id }
        update()
    }

    func open(_ reminder: Reminder) {
        dismiss(reminder)
        onOpen?(reminder.page, reminder.note)
    }

    /// Read again on a change, such as a todo ticked or given another time from the page.
    func readTodos() {
        todos = todoFile.map { Reminder.todos(TodoList.parse($0.read() ?? "")) } ?? []
        update()
    }

    public func readMeetings() {
        meetings = noteFolder.map { Reminder.meetings($0.notes()) } ?? []
        update()
    }

    private func update() {
        wait?.cancel()
        wait = nil
        let now = Date()
        let all = todos + meetings + answers
        showTab(ReminderSchedule.showing(all, at: now, dismissed: dismissed))
        guard let next = ReminderSchedule.nextChange(all, after: now, dismissed: dismissed) else { return }
        wait = Task { [weak self] in
            try? await Task.sleep(for: .seconds(next.timeIntervalSinceNow))
            guard !Task.isCancelled else { return }
            self?.update()
        }
    }

    private func showTab(_ showing: [Reminder]) {
        guard let first = showing.first else {
            tab?.orderOut(nil)
            tab = nil
            return
        }
        if tab == nil {
            let screen = NSScreen.screens.first { $0.auxiliaryTopRightArea != nil } ?? NSScreen.main
            guard let screen else { return }
            tab = ReminderTabWindow(reminders: self, on: screen)
        }
        tab?.show(first, more: showing.count - 1)
        tab?.orderFrontRegardless()
    }
}
