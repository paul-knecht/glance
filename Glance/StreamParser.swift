import Foundation

// One piece of news from Claude's streamed answer.
enum StreamEvent: Equatable {
    case text(String)     // the next few characters of the answer
    case stop(String)     // the answer ended, with the reason (for example "end_turn")
    case error(String)    // the API reported an error, with its type
    case ignore           // anything we don't need
}

// Claude sends its answer as a stream of lines. The interesting ones look
// like `data: {...}` with a small JSON object. This turns one line into a StreamEvent.
enum StreamParser {

    // The few fields of a stream line that we read.
    private struct Line: Decodable {
        let type: String
        let delta: Delta?
        let error: APIError?

        struct Delta: Decodable {
            let type: String?
            let text: String?
            let stop_reason: String?
        }

        struct APIError: Decodable {
            let type: String
        }
    }

    static func event(fromLine line: String) -> StreamEvent {
        guard line.hasPrefix("data:") else { return .ignore }
        let json = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard let parsed = try? JSONDecoder().decode(Line.self, from: Data(json.utf8)) else {
            return .ignore
        }

        switch parsed.type {
        case "content_block_delta":
            if parsed.delta?.type == "text_delta", let text = parsed.delta?.text {
                return .text(text)
            }
            return .ignore
        case "message_delta":
            if let reason = parsed.delta?.stop_reason {
                return .stop(reason)
            }
            return .ignore
        case "error":
            return .error(parsed.error?.type ?? "unknown")
        default:
            return .ignore
        }
    }
}

// Decides what each StreamEvent means for the answer: text to show, an
// error to report, or nothing. It also notices a stream that just stops.
struct StreamReducer {

    // Set once Claude has told us why the answer ended.
    private var sawStop = false

    // Returns text to add to the answer, or nil. Throws when the answer failed.
    mutating func handle(_ event: StreamEvent) throws -> String? {
        switch event {
        case .text(let text):
            return text
        case .stop(let reason):
            sawStop = true
            if reason == "refusal" { throw ClaudeError.refused }
            if reason == "max_tokens" { return "\n(The answer was cut off.)" }
            return nil
        case .error(let type):
            if type == "overloaded_error" || type == "rate_limit_error" { throw ClaudeError.busy }
            throw ClaudeError.failed
        case .ignore:
            return nil
        }
    }

    // Call when the stream has ended. A stream without a stop reason was cut off.
    func finish() throws {
        if !sawStop { throw ClaudeError.failed }
    }
}
