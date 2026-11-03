import AppKit
import Settings
import SwiftUI

/// Opens and closes the Claude page, and asks Claude Code the questions typed into it.
///
/// Nothing runs while no question is being answered. An answer still arriving when the panel closes
/// goes on arriving, and the conversation is there on the next open, until the user goes back to the
/// list of chats. Each chat is saved as its answers end, and can be picked up from that list.
@MainActor
@Observable
public final class ClaudeController {
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
    /// Pressing ⌘⇧C anywhere. The shortcut is registered only while this is set.
    public var onShortcut: (@MainActor () -> Void)? {
        didSet {
            shortcut?.unregister()
            shortcut = onShortcut.flatMap { action in HotKey(.claude, action: action) }
        }
    }

    private let settings: SettingsStore
    private let page = ClaudePage()
    private let panel = PagePanel<ClaudePage>()
    private var duration: TimeInterval?
    private var shortcut: HotKey?
    private var closesOnLeave = true
    /// The conversation showing, `nil` while the list of chats is.
    private var chat: ClaudeChat?
    /// Picked on the page for the next new chat only, over the folder set in Settings.
    private var pickedFolder: String?
    private var run: ClaudeRun?

    public init(settings: SettingsStore) {
        self.settings = settings
        panel.pageButton.current = .claude
        page.onAsk = { [weak self] question in self?.ask(question) }
        page.onStop = { [weak self] in self?.run?.stop() }
        page.onBack = { [weak self] in self?.backToChats() }
        page.onPick = { [weak self] in self?.pickUp($0) }
        page.onHandOff = { [weak self] in self?.handOff() }
        page.onPickFolder = { [weak self] in self?.pickFolder($0) }
        page.onChooseFolder = { [weak self] in Task { await self?.chooseFolder() } }
        page.onResize = { [weak self] in self.map { $0.panel.fit($0.page) } }
        panel.mayCloseOnLeave = { [weak self] in self.map { $0.closesOnLeave && $0.page.isIdle } ?? true }
        panel.onDismiss = { [weak self] in Task { await self?.close() } }
        panel.onClickOutsideMenu = { [weak self] in
            guard let page = self?.page, page.isChoosingFolder else { return false }
            page.isChoosingFolder = false
            return true
        }
        panel.onEscape = { [weak self] in
            guard let self else { return }
            if page.isChoosingFolder {
                page.isChoosingFolder = false
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
    public func open(
        on screen: NSScreen? = nil, from start: CGRect? = nil, closesOnLeave: Bool = true,
        onceCovered: @MainActor () async -> Void = {}
    ) async {
        guard !isOpen else { return }
        isOpen = true
        self.closesOnLeave = closesOnLeave
        page.chats = ClaudeChats.all()
        showFolders()
        duration = settings.preferences.animateBar ? settings.preferences.barAnimationDuration : nil
        await panel.open(page, on: screen, over: duration, from: start, onceCovered: onceCovered)
    }

    /// Takes the page back into the notch, or, given `items`, into the panel `items` brings up
    /// underneath it; without `animated`, at once.
    public func close(animated: Bool = true, into items: ((@escaping Shaping) async -> Void)? = nil) async {
        guard isOpen else { return }
        isOpen = false
        page.isChoosingFolder = false
        await panel.close(over: animated ? duration : nil, into: items)
    }

    /// The panel's frame while it is open, in AppKit screen coordinates: what the next page grows
    /// out of when switched to.
    public var panelFrame: CGRect? { panel.frame }

    private var settingsFolder: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        return ClaudeChat.trimmed(settings.preferences.claudeFolder ?? home)
    }

    private func showFolders() {
        page.folder = pickedFolder ?? settingsFolder
        page.folders = [settingsFolder] + ClaudeChat.folders(of: page.chats, besides: settingsFolder)
    }

    private func pickFolder(_ folder: String) {
        pickedFolder = folder == settingsFolder ? nil : folder
        page.isChoosingFolder = false
        showFolders()
    }

    /// The Open dialog would take the page's focus, which closes it; so the page goes, and comes back.
    private func chooseFolder() async {
        await close()
        let dialog = NSOpenPanel()
        dialog.canChooseFiles = false
        dialog.canChooseDirectories = true
        dialog.prompt = "Choose"
        dialog.directoryURL = URL(filePath: pickedFolder ?? settingsFolder)
        NSApp.activate(ignoringOtherApps: true)
        if dialog.runModal() == .OK, let url = dialog.url {
            pickedFolder = ClaudeChat.trimmed(url.path(percentEncoded: false))
        }
        await open(closesOnLeave: closesOnLeave)
    }

    /// In the chat showing, in the folder it began in, or in a new one in the folder picked for it.
    private func ask(_ question: String) {
        var chat = chat ?? ClaudeChat(
            id: "", folder: pickedFolder ?? settingsFolder, title: ClaudeChat.title(for: question), updated: .now,
            exchanges: []
        )
        if self.chat == nil { pickedFolder = nil }
        let resuming = chat.id.isEmpty ? nil : chat.id
        chat.updated = .now
        self.chat = chat
        let index = page.exchanges.count
        page.exchanges.append(ClaudeExchange(id: index, question: question))
        let run = ClaudeRun()
        self.run = run
        Task { [weak self] in
            let outcome = await run.ask(
                question, in: chat.folder, resuming: resuming, naming: resuming == nil ? chat.sessionName : nil
            ) { event in
                self?.take(event, into: index)
            }
            guard let self, page.exchanges.indices.contains(index), page.exchanges[index].id == index else { return }
            if self.run === run { self.run = nil }
            var exchange = page.exchanges[index]
            if !exchange.isAnswered, exchange.failure == nil {
                exchange.failure = outcome.status == 0 ? "Stopped." : Self.failure(outcome)
            }
            exchange.isAnswered = true
            page.exchanges[index] = exchange
            save()
        }
    }

    private func take(_ event: ClaudeEvent, into index: Int) {
        guard page.exchanges.indices.contains(index), page.exchanges[index].id == index else { return }
        var exchange = page.exchanges[index]
        switch event {
        case .session(let id):
            chat?.id = id
            page.canHandOff = true
        case .textStart:
            exchange.activity = nil
            if !exchange.answer.isEmpty { exchange.answer += "\n\n" }
        case .text(let text):
            exchange.answer += text
        case .tool(let name):
            exchange.activity = name
        case .result(let text, let isError):
            if isError {
                exchange.failure = text.isEmpty ? "Claude could not answer." : text
            } else if exchange.answer.isEmpty {
                exchange.answer = text
            }
            exchange.activity = nil
            exchange.isAnswered = true
        }
        page.exchanges[index] = exchange
    }

    private func save() {
        guard var chat else { return }
        chat.exchanges = page.exchanges
        chat.updated = .now
        self.chat = chat
        ClaudeChats.save(chat)
    }

    /// Stops an answer still arriving, keeping what came of it.
    private func backToChats() {
        if let run {
            run.stop()
            self.run = nil
            if let last = page.exchanges.indices.last, !page.exchanges[last].isAnswered {
                page.exchanges[last].isAnswered = true
                page.exchanges[last].activity = nil
                if page.exchanges[last].answer.isEmpty { page.exchanges[last].failure = "Stopped." }
            }
            // Answers that ended were saved then; resaving them would date the chat to now.
            save()
        }
        chat = nil
        page.exchanges = []
        page.canHandOff = false
        page.chats = ClaudeChats.all()
        showFolders()
        page.focusRequests += 1
    }

    private func pickUp(_ picked: ClaudeChat) {
        chat = picked
        // Numbered by position, which is how an answer arriving finds its exchange.
        page.exchanges = picked.exchanges.enumerated().map { index, exchange in
            var exchange = exchange
            exchange.id = index
            return exchange
        }
        page.canHandOff = true
        page.focusRequests += 1
    }

    /// Not while an answer is arriving, which the terminal's session would then race.
    private func handOff() {
        guard let chat, !chat.id.isEmpty, !page.isAnswering else { return }
        TerminalHandoff.open(session: chat.id, in: chat.folder)
        Task { await close() }
    }

    /// Why Claude did not answer, in the shell's words; a missing `claude` is the likely cause.
    private static func failure(_ outcome: (status: Int32, errors: String)) -> String {
        if outcome.status == 127 || outcome.errors.contains("command not found") {
            return "Claude Code is not installed, or not on your login shell's path."
        }
        return outcome.errors.isEmpty ? "Claude stopped with status \(outcome.status)." : outcome.errors
    }
}
