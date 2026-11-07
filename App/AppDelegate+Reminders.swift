import BouncerFoundation
import Settings
import Todos

extension AppDelegate {
    /// Reminders for the pages that are on, from the file and folder picked for them; a click opens the
    /// page, and a page opening marks its reminders seen.
    func wireReminders() {
        reminders.onOpen = { [weak self] page, note in self?.showReminded(page, note: note) }
        notes.onChange = { [weak self] in self?.reminders.readMeetings() }
        claude.onAnswer = { [weak self] in self?.reminders.claudeAnswered($0) }
        reminderSources = ObservationLoop { [weak self] in
            guard let self else { return }
            if claude.isOpen { reminders.seen(.claude) }
            reminders.follow(settings.preferences)
        }
    }

    private func showReminded(_ page: NotchPage, note: String?) {
        if let note { notes.show(note: note) }
        guard openPage != page else { return }
        if openPage == nil { toggle(page) } else { switchPage(to: page) }
    }
}
