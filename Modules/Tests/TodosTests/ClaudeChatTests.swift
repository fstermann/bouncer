import Foundation
import Testing

@testable import Todos

@Suite struct ClaudeChatTests {
    @Test func theTitleIsTheQuestionsFirstLineCutShort() {
        #expect(ClaudeChat.title(for: "What changed?\nIn detail please") == "What changed?")
        let long = String(repeating: "a", count: 100)
        #expect(ClaudeChat.title(for: long) == String(repeating: "a", count: 79) + "…")
    }

    @Test func pastFoldersComeNewestFirstOnceEachWithoutTheDefault() {
        let chats = [("/a", 1.0), ("/home", 5), ("/b/", 4), ("/a", 3)].map { folder, time in
            ClaudeChat(id: "", folder: folder, title: "", updated: Date(timeIntervalSince1970: time), exchanges: [])
        }
        #expect(ClaudeChat.folders(of: chats, besides: "/home") == ["/b", "/a"])
        #expect(ClaudeChat.folders(of: chats, besides: "/home/") == ["/b", "/a"])
    }

    @Test func theHandoffResumesInTheChatsFolderThroughTheLoginShell() {
        let script = TerminalHandoff.script(shell: "/bin/zsh", folder: "/Users/me/Bob's notes", session: "abc-123")
        #expect(script.hasPrefix("#!/bin/sh\nunset CLAUDECODE CLAUDE_CODE_CHILD_SESSION\n"))
        #expect(script.contains(#"exec '/bin/zsh' -lic 'cd "$1" && claude --resume "$2"' claude"#))
        #expect(script.contains(#"'/Users/me/Bob'\''s notes' 'abc-123'"#))
    }
}
