import XCTest
@testable import Glance

// Checks that each line of Claude's streamed answer is understood.
// The sample lines follow the format in Anthropic's API documentation.
final class StreamParserTests: XCTestCase {

    func testMessageStartIsIgnored() {
        let line = #"data: {"type":"message_start","message":{"id":"msg_1","type":"message"}}"#
        XCTAssertEqual(StreamParser.event(fromLine: line), .ignore)
    }

    func testBlockStartIsIgnored() {
        let line = #"data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#
        XCTAssertEqual(StreamParser.event(fromLine: line), .ignore)
    }

    func testTextDelta() {
        let line = #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}"#
        XCTAssertEqual(StreamParser.event(fromLine: line), .text("Hello"))
    }

    func testTextDeltaWithEscapesAndUmlauts() {
        let line = #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"allgegenwärtig\n\"x\""}}"#
        XCTAssertEqual(StreamParser.event(fromLine: line), .text("allgegenwärtig\n\"x\""))
    }

    func testThinkingDeltaIsIgnored() {
        let line = #"data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"hm"}}"#
        XCTAssertEqual(StreamParser.event(fromLine: line), .ignore)
    }

    func testBlockStopIsIgnored() {
        XCTAssertEqual(StreamParser.event(fromLine: #"data: {"type":"content_block_stop","index":0}"#), .ignore)
    }

    func testStopReason() {
        let line = #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":12}}"#
        XCTAssertEqual(StreamParser.event(fromLine: line), .stop("end_turn"))
    }

    func testMessageStopIsIgnored() {
        XCTAssertEqual(StreamParser.event(fromLine: #"data: {"type":"message_stop"}"#), .ignore)
    }

    func testEventLinesAndEmptyLinesAreIgnored() {
        XCTAssertEqual(StreamParser.event(fromLine: "event: content_block_delta"), .ignore)
        XCTAssertEqual(StreamParser.event(fromLine: ""), .ignore)
    }

    func testErrorEvent() {
        let line = #"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#
        XCTAssertEqual(StreamParser.event(fromLine: line), .error("overloaded_error"))
    }

    func testGarbageIsIgnored() {
        XCTAssertEqual(StreamParser.event(fromLine: "data: not json"), .ignore)
    }

    func testDataWithoutSpaceAfterColon() {
        let line = #"data:{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi"}}"#
        XCTAssertEqual(StreamParser.event(fromLine: line), .text("Hi"))
    }
}
