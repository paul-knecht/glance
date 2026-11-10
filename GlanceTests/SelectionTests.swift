import XCTest
@testable import Glance

// Checks the rule that decides whether a selection is "a word" or "a passage".
final class SelectionTests: XCTestCase {

    private func selection(_ text: String) -> Selection {
        Selection(text: text, context: nil, anchor: nil)
    }

    func testSingleWordIsWord() {
        XCTAssertTrue(selection("ubiquitous").isWord)
    }

    func testTwoWordPhraseIsWord() {
        XCTAssertTrue(selection("loss aversion").isWord)
    }

    func testFourWordsIsPassage() {
        XCTAssertFalse(selection("one two three four").isWord)
    }

    func testVeryLongTokenIsPassage() {
        XCTAssertFalse(selection(String(repeating: "a", count: 61)).isWord)
    }

    func testTextIsTrimmed() {
        let s = selection("  word \n")
        XCTAssertEqual(s.text, "word")
        XCTAssertTrue(s.isWord)
    }

    func testMaxLength() {
        XCTAssertEqual(Selection.maxLength, 20_000)
    }
}
