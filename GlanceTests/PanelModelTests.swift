import XCTest
@testable import Glance

// Checks the panel's behaviour with a pretend Claude, so no test uses the network.
@MainActor
final class PanelModelTests: XCTestCase {

    // A pretend Claude. It records every request and answers with the chunks
    // we give it. With `hold` set, a request waits until `release()` is called.
    final class FakeClaude {
        var calls: [(system: String, user: String, key: String?)] = []
        var chunks: [String] = ["Hello", " world"]
        var error: Error?
        var hold = false
        private var waiting: [() -> Void] = []

        func stream(system: String, user: String, key: String?) -> AsyncThrowingStream<String, Error> {
            calls.append((system, user, key))
            let chunks = self.chunks
            let error = self.error
            return AsyncThrowingStream { continuation in
                let send = {
                    for chunk in chunks { continuation.yield(chunk) }
                    continuation.finish(throwing: error)
                }
                if self.hold { self.waiting.append(send) } else { send() }
            }
        }

        func release() {
            waiting.forEach { $0() }
            waiting = []
        }
    }

    private var claude: FakeClaude!
    private var model: PanelModel!

    private let word = Selection(text: "ubiquitous", context: nil, anchor: nil)
    private let passage = Selection(text: "Losses hurt more than equal gains feel good.", context: nil, anchor: nil)

    override func setUp() {
        claude = FakeClaude()
        model = PanelModel(loadKey: { "test-key" }, stream: { [claude] system, user, key in
            claude!.stream(system: system, user: user, key: key)
        })
    }

    // Lets the model's background tasks run until they have nothing left to do.
    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(nanoseconds: 20_000_000)
        for _ in 0..<20 { await Task.yield() }
    }

    func testOpenLoadsExplainOnly() async {
        model.open(selection: passage, hasPermission: true)
        await settle()
        XCTAssertEqual(claude.calls.count, 1)
        XCTAssertEqual(claude.calls[0].user, Prompts.user(for: .explain, selection: passage))
        XCTAssertEqual(claude.calls[0].system, Prompts.system)
        XCTAssertEqual(claude.calls[0].key, "test-key")
        XCTAssertEqual(model.answers[.explain], .done("Hello world"))
        XCTAssertEqual(model.answers[.translate], .idle)
        XCTAssertEqual(model.selectedTab, .explain)
        XCTAssertNil(model.notice)
    }

    func testTabLoadsOnceOnFirstSelect() async {
        model.open(selection: passage, hasPermission: true)
        await settle()
        model.select(.translate)
        await settle()
        model.select(.explain)
        model.select(.translate)
        await settle()
        XCTAssertEqual(claude.calls.count, 2)
        XCTAssertEqual(claude.calls[1].user, Prompts.user(for: .translate, selection: passage))
        XCTAssertEqual(model.answers[.translate], .done("Hello world"))
        XCTAssertEqual(model.selectedTab, .translate)
    }

    func testNoPermissionMakesNoRequest() async {
        model.open(selection: nil, hasPermission: false)
        await settle()
        XCTAssertEqual(model.notice, .needsPermission)
        XCTAssertEqual(claude.calls.count, 0)
    }

    func testNothingSelectedMakesNoRequest() async {
        model.open(selection: nil, hasPermission: true)
        await settle()
        XCTAssertEqual(model.notice, .nothingSelected)
        model.open(selection: Selection(text: "  \n ", context: nil, anchor: nil), hasPermission: true)
        await settle()
        XCTAssertEqual(model.notice, .nothingSelected)
        XCTAssertEqual(claude.calls.count, 0)
    }

    func testTooLongMakesNoRequestButLimitItselfIsFine() async {
        model.open(selection: Selection(text: String(repeating: "a", count: 20_001), context: nil, anchor: nil), hasPermission: true)
        await settle()
        XCTAssertEqual(model.notice, .tooLong)
        XCTAssertEqual(claude.calls.count, 0)

        model.open(selection: Selection(text: String(repeating: "a", count: 20_000), context: nil, anchor: nil), hasPermission: true)
        await settle()
        XCTAssertNil(model.notice)
        XCTAssertEqual(claude.calls.count, 1)
    }

    func testNoticesBlockTabsAndQuestions() async {
        model.open(selection: nil, hasPermission: true)
        model.select(.translate)
        model.question = "Why?"
        model.ask()
        await settle()
        XCTAssertEqual(claude.calls.count, 0)
    }

    func testErrorKeepsTextAndShowsMessage() async {
        claude.chunks = ["Hi"]
        claude.error = ClaudeError.offline
        model.open(selection: passage, hasPermission: true)
        await settle()
        XCTAssertEqual(model.answers[.explain], .failed(text: "Hi", message: "No internet connection."))
    }

    func testUnknownErrorUsesGeneralMessage() async {
        claude.chunks = []
        claude.error = URLError(.badURL)
        model.open(selection: passage, hasPermission: true)
        await settle()
        XCTAssertEqual(model.answers[.explain], .failed(text: "", message: "Something went wrong. Try again."))
    }

    func testFailedTabLoadsAgainWhenSelectedAgain() async {
        claude.chunks = []
        claude.error = ClaudeError.busy
        model.open(selection: passage, hasPermission: true)
        await settle()
        claude.chunks = ["ok"]
        claude.error = nil
        model.select(.explain)
        await settle()
        XCTAssertEqual(model.answers[.explain], .done("ok"))
    }

    func testLateChunksAfterReopenAreDropped() async {
        claude.hold = true
        claude.chunks = ["from A"]
        model.open(selection: passage, hasPermission: true)
        await settle()
        claude.chunks = ["from B"]
        model.open(selection: word, hasPermission: true)
        await settle()
        claude.release()
        await settle()
        XCTAssertEqual(model.selection, word)
        XCTAssertEqual(model.answers[.explain], .done("from B"))
    }

    func testCloseCancels() async {
        claude.hold = true
        model.open(selection: passage, hasPermission: true)
        await settle()
        model.close()
        claude.release()
        await settle()
        XCTAssertEqual(model.answers[.explain], .idle)
    }

    func testAskStreamsIntoQuestionAnswer() async {
        model.open(selection: passage, hasPermission: true)
        await settle()
        model.question = "  Who said this? "
        model.ask()
        await settle()
        XCTAssertEqual(claude.calls.count, 2)
        XCTAssertEqual(claude.calls[1].user, Prompts.user(question: "Who said this?", selection: passage))
        XCTAssertEqual(model.questionAnswer, .done("Hello world"))
    }

    func testBlankQuestionIgnored() async {
        model.open(selection: passage, hasPermission: true)
        await settle()
        model.question = "   "
        model.ask()
        await settle()
        XCTAssertEqual(claude.calls.count, 1)
        XCTAssertEqual(model.questionAnswer, .idle)
    }

    func testSecondQuestionReplacesFirst() async {
        model.open(selection: passage, hasPermission: true)
        await settle()
        claude.hold = true
        claude.chunks = ["first"]
        model.question = "One?"
        model.ask()
        await settle()
        claude.chunks = ["second"]
        model.question = "Two?"
        model.ask()
        await settle()
        claude.release()
        await settle()
        XCTAssertEqual(model.questionAnswer, .done("second"))
    }

    func testTextToCopyFollowsLastAction() async {
        model.open(selection: passage, hasPermission: true)
        await settle()
        XCTAssertEqual(model.textToCopy, "Hello world")

        claude.chunks = ["An answer"]
        model.question = "Why?"
        model.ask()
        await settle()
        XCTAssertEqual(model.textToCopy, "An answer")

        claude.chunks = ["Übersetzung"]
        model.select(.translate)
        await settle()
        XCTAssertEqual(model.textToCopy, "Übersetzung")
    }

    func testTextToCopyForWordUsesLabelLines() async {
        claude.chunks = ["PART: adjective\nDEFINITION: Everywhere.\n", "GERMAN: allgegenwärtig"]
        model.open(selection: word, hasPermission: true)
        await settle()
        XCTAssertEqual(model.textToCopy, "Definition: Everywhere.\nGerman: allgegenwärtig")
    }

    // After ⌘C the footer says "Copied" until the next look-up.
    func testNoteCopiedSetsFlagAndOpenClearsIt() {
        XCTAssertFalse(model.justCopied)
        model.noteCopied()
        XCTAssertTrue(model.justCopied)
        model.open(selection: passage, hasPermission: true)
        XCTAssertFalse(model.justCopied)
    }

    func testTextToCopyIsNilWithoutAnswer() {
        model.open(selection: nil, hasPermission: true)
        XCTAssertNil(model.textToCopy)
    }
}
