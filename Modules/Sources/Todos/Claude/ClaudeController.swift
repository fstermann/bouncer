import AppKit
import Settings
import SwiftUI

/// Opens and closes the Claude page, and asks Claude Code the questions typed into it.
///
/// Nothing runs while no question is being answered. An answer still arriving when the panel closes
/// goes on arriving, and the conversation is there on the next open, until a new one is started.
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
    /// The conversation the next question is asked in, and the folder it was started in.
    private var session: (id: String, folder: String)?
    private var run: ClaudeRun?

    public init(settings: SettingsStore) {
        self.settings = settings
        panel.pageButton.current = .claude
        page.onAsk = { [weak self] question in self?.ask(question) }
        page.onStop = { [weak self] in self?.run?.stop() }
        page.onNew = { [weak self] in self?.startOver() }
        page.onResize = { [weak self] in self.map { $0.panel.fit($0.page) } }
        panel.mayCloseOnLeave = { [weak self] in self.map { $0.closesOnLeave && $0.page.isIdle } ?? true }
        panel.onDismiss = { [weak self] in Task { await self?.close() } }
        panel.onEscape = { [weak self] in Task { await self?.close() } }
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
        page.folderName = URL(filePath: folder).lastPathComponent
        duration = settings.preferences.animateBar ? settings.preferences.barAnimationDuration : nil
        await panel.open(page, on: screen, over: duration, from: start, onceCovered: onceCovered)
    }

    /// Takes the page back into the notch, or, given `items`, into the panel `items` brings up
    /// underneath it; without `animated`, at once.
    public func close(animated: Bool = true, into items: ((@escaping Shaping) async -> Void)? = nil) async {
        guard isOpen else { return }
        isOpen = false
        await panel.close(over: animated ? duration : nil, into: items)
    }

    /// The panel's frame while it is open, in AppKit screen coordinates: what the next page grows
    /// out of when switched to.
    public var panelFrame: CGRect? { panel.frame }

    private var folder: String {
        settings.preferences.claudeFolder ?? FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
    }

    /// In the conversation so far, unless the folder has changed since it began.
    private func ask(_ question: String) {
        let folder = folder
        if session?.folder != folder { session = nil }
        let index = page.exchanges.count
        page.exchanges.append(ClaudeExchange(id: index, question: question))
        let run = ClaudeRun()
        self.run = run
        Task { [weak self] in
            let outcome = await run.ask(question, in: folder, resuming: self?.session?.id) { event in
                self?.take(event, into: index, folder: folder)
            }
            guard let self, page.exchanges.indices.contains(index), page.exchanges[index].id == index else { return }
            if self.run === run { self.run = nil }
            var exchange = page.exchanges[index]
            if !exchange.isAnswered, exchange.failure == nil {
                exchange.failure = outcome.status == 0 ? "Stopped." : Self.failure(outcome)
            }
            exchange.isAnswered = true
            page.exchanges[index] = exchange
        }
    }

    private func take(_ event: ClaudeEvent, into index: Int, folder: String) {
        guard page.exchanges.indices.contains(index), page.exchanges[index].id == index else { return }
        var exchange = page.exchanges[index]
        switch event {
        case .session(let id):
            session = (id, folder)
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

    private func startOver() {
        run?.stop()
        run = nil
        session = nil
        page.exchanges = []
        page.focusRequests += 1
    }

    /// Why Claude did not answer, in the shell's words; a missing `claude` is the likely cause.
    private static func failure(_ outcome: (status: Int32, errors: String)) -> String {
        if outcome.status == 127 || outcome.errors.contains("command not found") {
            return "Claude Code is not installed, or not on your login shell's path."
        }
        return outcome.errors.isEmpty ? "Claude stopped with status \(outcome.status)." : outcome.errors
    }
}
