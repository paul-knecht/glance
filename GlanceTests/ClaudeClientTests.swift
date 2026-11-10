import XCTest
@testable import Glance

// Checks the request we build for Claude and how failures are named.
// None of these tests talks to the real API.
final class ClaudeClientTests: XCTestCase {

    private func body() throws -> [String: Any] {
        let data = try ClaudeClient.requestBody(system: "SYS", user: "USER")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testBodyBasics() throws {
        let body = try body()
        XCTAssertEqual(body["model"] as? String, "claude-haiku-5-5")
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual(body["system"] as? String, "SYS")
        XCTAssertEqual(body["max_tokens"] as? Int, 16000)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["role"] as? String, "user")
        XCTAssertEqual(messages[0]["content"] as? String, "USER")
    }

    func testBodyAsksForFastAnswers() throws {
        let body = try body()
        XCTAssertEqual((body["thinking"] as? [String: Any])?["type"] as? String, "disabled")
        XCTAssertEqual((body["output_config"] as? [String: Any])?["effort"] as? String, "low")
    }

    func testBodyLeavesOutFieldsHaikuRejects() throws {
        let body = try body()
        for field in ["temperature", "top_p", "top_k", "fallbacks"] {
            XCTAssertNil(body[field], "\(field) must not be sent")
        }
    }

    func testErrorForStatusCodes() {
        let empty = Data()
        XCTAssertEqual(ClaudeClient.error(statusCode: 401, body: empty), .unauthorized)
        XCTAssertEqual(ClaudeClient.error(statusCode: 402, body: empty), .noCredit)
        XCTAssertEqual(ClaudeClient.error(statusCode: 429, body: empty), .busy)
        XCTAssertEqual(ClaudeClient.error(statusCode: 529, body: empty), .busy)
        XCTAssertEqual(ClaudeClient.error(statusCode: 500, body: empty), .failed)
        XCTAssertEqual(ClaudeClient.error(statusCode: 400, body: empty), .failed)
    }

    func testCreditBalanceErrorIsNoCredit() {
        let body = Data(#"{"type":"error","error":{"type":"invalid_request_error","message":"Your credit balance is too low to access the Anthropic API."}}"#.utf8)
        XCTAssertEqual(ClaudeClient.error(statusCode: 400, body: body), .noCredit)
    }

    func testStreamWithoutKeyThrowsNoKey() async {
        for key in [nil, "", "   "] as [String?] {
            do {
                for try await _ in ClaudeClient.stream(system: "s", user: "u", apiKey: key) {}
                XCTFail("expected an error")
            } catch {
                XCTAssertEqual(error as? ClaudeError, .noKey)
            }
        }
    }

    func testMessages() {
        XCTAssertEqual(ClaudeError.noKey.message, "Add an Anthropic API key to get answers: open the Glance app again and choose Set API key.")
        XCTAssertEqual(ClaudeError.offline.message, "No internet connection.")
        XCTAssertEqual(ClaudeError.unauthorized.message, "The API key was not accepted. Open the Glance app again and set it once more.")
        XCTAssertEqual(ClaudeError.noCredit.message, "Your Anthropic account has no credit. Add credit in the Anthropic Console.")
        XCTAssertEqual(ClaudeError.busy.message, "Claude is busy right now. Try again in a moment.")
        XCTAssertEqual(ClaudeError.refused.message, "Claude declined to answer this.")
        XCTAssertEqual(ClaudeError.failed.message, "Something went wrong. Try again.")
    }

    // What happens to the text chunks and the end of a stream.
    func testReduceCollectsTextUntilStop() throws {
        var reducer = StreamReducer()
        XCTAssertEqual(try reducer.handle(.text("Hel")), "Hel")
        XCTAssertNil(try reducer.handle(.ignore))
        XCTAssertNil(try reducer.handle(.stop("end_turn")))
        XCTAssertNoThrow(try reducer.finish())
    }

    func testReduceRefusalThrows() {
        var reducer = StreamReducer()
        XCTAssertThrowsError(try reducer.handle(.stop("refusal"))) { XCTAssertEqual($0 as? ClaudeError, .refused) }
    }

    func testReduceMaxTokensAddsNote() throws {
        var reducer = StreamReducer()
        XCTAssertEqual(try reducer.handle(.stop("max_tokens")), "\n(The answer was cut off.)")
        XCTAssertNoThrow(try reducer.finish())
    }

    func testReduceErrorEvents() {
        var reducer = StreamReducer()
        XCTAssertThrowsError(try reducer.handle(.error("overloaded_error"))) { XCTAssertEqual($0 as? ClaudeError, .busy) }
        XCTAssertThrowsError(try reducer.handle(.error("rate_limit_error"))) { XCTAssertEqual($0 as? ClaudeError, .busy) }
        XCTAssertThrowsError(try reducer.handle(.error("api_error"))) { XCTAssertEqual($0 as? ClaudeError, .failed) }
    }

    // A connection that drops mid-answer ends the stream without a stop reason.
    func testReduceEndingWithoutStopFails() {
        var reducer = StreamReducer()
        _ = try? reducer.handle(.text("partial"))
        XCTAssertThrowsError(try reducer.finish()) { XCTAssertEqual($0 as? ClaudeError, .failed) }
    }
}
