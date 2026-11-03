import Testing

@testable import Todos

@Suite struct ClaudeStreamTests {
    /// A line of the stream carrying one API event, from the answer itself or from a subagent's.
    private func streamed(_ event: String, parent: String = "null") -> String {
        #"{"type":"stream_event","event":\#(event),"parent_tool_use_id":\#(parent)}"#
    }

    @Test func theInitGivesTheSession() {
        let line = #"{"type":"system","subtype":"init","cwd":"/x","session_id":"abc","tools":[]}"#
        #expect(ClaudeStream.event(from: line) == .session("abc"))
        #expect(ClaudeStream.event(from: #"{"type":"system","subtype":"status","session_id":"abc"}"#) == nil)
    }

    @Test func textArrivesInDeltasAfterItsBlockStarts() {
        let start = streamed(#"{"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}"#)
        let delta = streamed(#"{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"hi"}}"#)
        #expect(ClaudeStream.event(from: start) == .textStart)
        #expect(ClaudeStream.event(from: delta) == .text("hi"))
    }

    @Test func thinkingAndSubagentsAreLeftOut() {
        let thinking = streamed(#"{"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"hm"}}"#)
        let text = #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"x"}}"#
        #expect(ClaudeStream.event(from: thinking) == nil)
        #expect(ClaudeStream.event(from: streamed(text, parent: #""toolu_1""#)) == nil)
    }

    @Test func aToolInUseIsNamed() {
        let line = streamed(#"{"type":"content_block_start","content_block":{"type":"tool_use","name":"Read"}}"#)
        #expect(ClaudeStream.event(from: line) == .tool("Read"))
    }

    @Test func theResultEndsTheAnswer() {
        #expect(ClaudeStream.event(from: #"{"type":"result","is_error":false,"result":"hi"}"#)
            == .result("hi", isError: false))
        #expect(ClaudeStream.event(from: #"{"type":"result","is_error":true,"result":"Not logged in"}"#)
            == .result("Not logged in", isError: true))
    }

    @Test func whatTheShellPrintsIsNotJSON() {
        #expect(ClaudeStream.event(from: "Welcome back!") == nil)
        #expect(ClaudeStream.event(from: "") == nil)
    }
}
