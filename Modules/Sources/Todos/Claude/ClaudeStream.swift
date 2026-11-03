import Foundation

/// What `claude -p --output-format stream-json --include-partial-messages` reports, one JSON object a
/// line, as far as the page shows it. Pure over lines, so it is tested without running Claude.
enum ClaudeEvent: Equatable, Sendable {
    /// The conversation's ID, to ask the next question in.
    case session(String)
    /// A block of the answer begins, after a blank line if another came before it.
    case textStart
    case text(String)
    /// Claude is using a tool, such as reading a file, before it goes on answering.
    case tool(String)
    /// The whole answer, or what went wrong.
    case result(String, isError: Bool)
}

enum ClaudeStream {
    /// `nil` for a line the page has no use for, or one that is not JSON at all, which a login shell
    /// may print before Claude starts.
    static func event(from line: String) -> ClaudeEvent? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String
        else { return nil }
        switch type {
        case "system":
            guard object["subtype"] as? String == "init", let id = object["session_id"] as? String else { return nil }
            return .session(id)
        case "stream_event":
            // A subagent's own messages are its business; only the answer is shown.
            guard object["parent_tool_use_id"] == nil || object["parent_tool_use_id"] is NSNull,
                  let event = object["event"] as? [String: Any]
            else { return nil }
            return streamed(event)
        case "result":
            return .result(object["result"] as? String ?? "", isError: object["is_error"] as? Bool ?? false)
        default:
            return nil
        }
    }

    private static func streamed(_ event: [String: Any]) -> ClaudeEvent? {
        switch event["type"] as? String {
        case "content_block_start":
            guard let block = event["content_block"] as? [String: Any] else { return nil }
            switch block["type"] as? String {
            case "text": return .textStart
            case "tool_use": return (block["name"] as? String).map(ClaudeEvent.tool)
            default: return nil
            }
        case "content_block_delta":
            guard let delta = event["delta"] as? [String: Any], delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String
            else { return nil }
            return .text(text)
        default:
            return nil
        }
    }
}
