import Foundation
import Settings
import Testing

@testable import Todos

@Suite @MainActor struct ClaudeQueueTests {
    @Test func findsTheTranscriptClaudeCodeKeepsForTheSessionsFolder() {
        let session = ClaudeSession(id: "abc", folder: "/Users/me/projects/private-gateway/my_app.v2")
        #expect(
            ClaudeQueue.transcript(of: session, home: "/Users/me/")
                == "/Users/me/.claude/projects/-Users-me-projects-private-gateway-my-app-v2/abc.jsonl"
        )
    }

    @Test func readsAndWritesTheInProgressBox() throws {
        let file = "- [/] Ship it\n- [x] Done ✅ 2026-11-01\n- [ ] Open"
        let todos = TodoList.parse(file)
        #expect(todos.map(\.isInProgress) == [true, false, false])
        #expect(todos.map(\.isDone) == [false, true, false])
        let reopened = try #require(TodoList.marking(todos[1], inProgress: true, in: file))
        #expect(reopened == "- [/] Ship it\n- [/] Done\n- [ ] Open")
        let open = try #require(TodoList.marking(todos[0], inProgress: false, in: file))
        #expect(open.hasPrefix("- [ ] Ship it\n"))
        let ticked = try #require(TodoList.toggling(todos[0], in: file, today: "2026-11-06"))
        #expect(ticked.hasPrefix("- [x] Ship it ✅ 2026-11-06\n"))
        let edited = try #require(TodoList.replacing(todos[0], with: "Ship it now", note: "", in: file))
        #expect(edited.hasPrefix("- [/] Ship it now\n"))
    }

    @Test func theMostSpecificLinkedTagPicksTheRepository() {
        let repositories = ["work": "/work", "work/bouncer": "/bouncer"]
        let nested = Todo(line: 0, text: "A #claude #work/bouncer", isDone: false)
        let parent = Todo(line: 1, text: "B #work/other #claude", isDone: false)
        let unlinked = Todo(line: 2, text: "C #claude", isDone: false)
        #expect(ClaudeQueue.repository(of: nested, in: repositories) == "/bouncer")
        #expect(ClaudeQueue.repository(of: parent, in: repositories) == "/work")
        let groups = ClaudeQueue.groups([nested, unlinked, parent, nested], repositories: repositories)
        #expect(groups.map(\.folder) == ["/bouncer", nil, "/work"])
        #expect(groups[0].todos.count == 2)
    }

    @Test func thePromptListsTitlesAndNotesThenTheBranchAndAsksHowToCommit() {
        let todo = Todo(line: 0, text: "Fix bar #claude 📅 2026-11-07", isDone: false, note: "Flickers\nOn wake")
        let prompt = ClaudeQueue.prompt(for: [todo], branch: "todos/20261113-1201")
        #expect(prompt.hasPrefix("Please implement these todos:\n\n- Fix bar\n  Flickers\n  On wake\n\n"))
        #expect(prompt.contains("named todos/20261113-1201."))
        #expect(prompt.contains("AskUserQuestion"))
    }

    @Test func thePromptGivesTheCopiedPathOfEachImage() {
        let todo = Todo(line: 0, text: "Fix ![[a.png]] #claude", isDone: false, note: "See ![[b.png|300]] ![[c.png]]")
        #expect(ClaudeQueue.imageNames(in: [todo]) == ["a.png", "b.png", "c.png"])
        let prompt = ClaudeQueue.prompt(for: [todo], images: ["a.png": "/t/a.png", "b.png": "/t/b.png"], branch: "b")
        #expect(prompt.hasPrefix("Please implement these todos:\n\n- Fix /t/a.png\n  See /t/b.png ![[c.png]]\n"))
    }

    @Test func theBranchIsStampedToTheMinute() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 4, hour: 9, minute: 5)) ?? .now
        #expect(ClaudeQueue.branch(at: date, calendar: calendar) == "todos/20260304-0905")
    }

    @Test func claudeTodosLeadTheListInTheirOwnGroups() {
        let page = TodoPage()
        let plain = Todo(line: 0, text: "Plain", isDone: false)
        let queued = Todo(line: 1, text: "Queued #claude", isDone: false)
        let working = Todo(line: 2, text: "Working #claude", isDone: false, isInProgress: true)
        page.todos = [plain, queued, working]
        #expect(page.sections.map(\.title) == ["For Claude", "Claude working", "Todos"])
        #expect(page.rows == [queued, working, plain])
        page.todos = [plain]
        #expect(page.sections.map(\.title) == [nil])
    }

    @Test func workingTodosAreGroupedByTheirSession() {
        let page = TodoPage()
        let one = Todo(line: 0, text: "A #claude", isDone: false, isInProgress: true)
        let two = Todo(line: 1, text: "B #claude", isDone: false, isInProgress: true)
        let other = Todo(line: 2, text: "C #claude", isDone: false, isInProgress: true)
        let unsaved = Todo(line: 3, text: "D #claude", isDone: false, isInProgress: true)
        let first = ClaudeSession(id: "s1", folder: "/r")
        page.todos = [one, two, other, unsaved]
        page.sessions = ["A": first, "B": first, "C": ClaudeSession(id: "s2", folder: "/q")]
        #expect(page.workingSessions.map(\.session.id) == ["s1", "s2"])
        #expect(page.workingSessions[0].todos == [one, two])
    }

    @Test func theNewSessionScriptAsksInTheRepository() {
        let script = TerminalHandoff.script(shell: "/bin/zsh", folder: "/r", prompt: "Please 'quote'", session: "s-1")
        #expect(script.contains(#"claude --session-id "$3" -- "$2"' claude '/r' 'Please '\''quote'\''' 's-1'"#))
    }

    @Test func aSessionIsKeptByTheTodosTitleOnly() {
        let sent = Todo(line: 0, text: "Fix bar #claude", isDone: false)
        let later = Todo(line: 4, text: "Fix bar #claude #bouncer 📅 2026-11-09", isDone: false, isInProgress: true)
        #expect(ClaudeQueue.key(of: sent) == ClaudeQueue.key(of: later))
    }
}
