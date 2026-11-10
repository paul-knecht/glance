import XCTest
@testable import Glance

// Checks that we cut out the right sentence around a selected word.
final class SentenceFinderTests: XCTestCase {

    private func find(_ word: String, in text: String) -> String? {
        guard let range = text.range(of: word) else { return nil }
        return SentenceFinder.sentence(in: text, around: range)
    }

    func testFindsMiddleSentence() {
        let text = "First one. Smartphones are ubiquitous today. Last."
        XCTAssertEqual(find("ubiquitous", in: text), "Smartphones are ubiquitous today.")
    }

    func testQuestionAndExclamationMarksEndSentences() {
        let text = "Really? Phones are ubiquitous! Yes."
        XCTAssertEqual(find("ubiquitous", in: text), "Phones are ubiquitous!")
    }

    func testNoTerminatorsReturnsWholeText() {
        XCTAssertEqual(find("ubiquitous", in: "phones are ubiquitous now"), "phones are ubiquitous now")
    }

    func testLineBreakIsBoundary() {
        let text = "A heading\nPhones are ubiquitous now\nAnother line"
        XCTAssertEqual(find("ubiquitous", in: text), "Phones are ubiquitous now")
    }

    func testSelectionCoveringEverythingGivesNil() {
        XCTAssertNil(find("ubiquitous", in: "ubiquitous"))
        XCTAssertNil(find("ubiquitous", in: "  ubiquitous. "))
    }

    func testFirstAndLastSentences() {
        let text = "Alpha is first. Beta is last"
        XCTAssertEqual(find("Alpha", in: text), "Alpha is first.")
        XCTAssertEqual(find("Beta", in: text), "Beta is last")
    }
}
