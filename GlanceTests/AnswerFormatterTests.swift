import XCTest
@testable import Glance

// Checks that a word look-up's labelled lines become the panel's sections,
// also while the answer is still arriving.
final class AnswerFormatterTests: XCTestCase {

    private func labels(_ text: String) -> [String?] {
        AnswerFormatter.wordSections(from: text).sections.map(\.label)
    }

    private func texts(_ text: String) -> [String] {
        AnswerFormatter.wordSections(from: text).sections.map(\.text)
    }

    func testFullAnswer() {
        let answer = """
        PART: adjective
        DEFINITION: Present or found everywhere.
        GERMAN: allgegenwärtig
        CONTEXT: Smartphones are everywhere.
        """
        let result = AnswerFormatter.wordSections(from: answer)
        XCTAssertEqual(result.part, "adjective")
        XCTAssertEqual(result.sections.map(\.label), ["Definition", "German", "In this sentence"])
        XCTAssertEqual(result.sections.map(\.text), ["Present or found everywhere.", "allgegenwärtig", "Smartphones are everywhere."])
    }

    func testEnglishAndUseLabels() {
        let answer = "PART: Adjektiv\nDEFINITION: Überall vorhanden.\nENGLISH: ubiquitous\nUSE: Oft über Technik."
        XCTAssertEqual(labels(answer), ["Definition", "English", "In use"])
    }

    func testMarkdownDecoratedAndLowercaseKeys() {
        let answer = "**PART:** noun\n- **Definition:** A thing.\n* german: Ding"
        let result = AnswerFormatter.wordSections(from: answer)
        XCTAssertEqual(result.part, "noun")
        XCTAssertEqual(result.sections.map(\.label), ["Definition", "German"])
        XCTAssertEqual(result.sections.map(\.text), ["A thing.", "Ding"])
    }

    func testContinuationLineJoinsPreviousSection() {
        let answer = "DEFINITION: First line.\nSecond line."
        XCTAssertEqual(texts(answer), ["First line.\nSecond line."])
    }

    func testPartialStreamShowsWhatHasArrived() {
        let result = AnswerFormatter.wordSections(from: "PART: adj\nDEFINITION: Pres")
        XCTAssertEqual(result.part, "adj")
        XCTAssertEqual(result.sections.map(\.text), ["Pres"])
    }

    func testKeyWithoutValueGivesNoSectionYet() {
        XCTAssertTrue(AnswerFormatter.wordSections(from: "PART: adj\nDEFINITION:").sections.isEmpty)
        XCTAssertTrue(AnswerFormatter.wordSections(from: "PART: adj\nDEFIN").sections.isEmpty)
    }

    func testTextWithoutKeysIsOneUnlabelledSection() {
        let result = AnswerFormatter.wordSections(from: "It means everywhere.")
        XCTAssertNil(result.part)
        XCTAssertEqual(result.sections.map(\.label), [nil])
        XCTAssertEqual(result.sections.map(\.text), ["It means everywhere."])
    }

    func testEmptyText() {
        let result = AnswerFormatter.wordSections(from: "")
        XCTAssertNil(result.part)
        XCTAssertTrue(result.sections.isEmpty)
    }

    func testBlankLinesAreSkipped() {
        XCTAssertEqual(texts("DEFINITION: One.\n\nGERMAN: Eins"), ["One.", "Eins"])
    }

    func testSectionIdsAreUnique() {
        let ids = AnswerFormatter.wordSections(from: "DEFINITION: a\nGERMAN: b\nCONTEXT: c").sections.map(\.id)
        XCTAssertEqual(Set(ids).count, 3)
    }

    func testPlainTextForCopying() {
        let answer = "PART: adjective\nDEFINITION: Everywhere.\nGERMAN: allgegenwärtig"
        XCTAssertEqual(AnswerFormatter.plainText(from: answer), "Definition: Everywhere.\nGerman: allgegenwärtig")
    }

    func testPlainTextWithoutKeysIsUnchanged() {
        XCTAssertEqual(AnswerFormatter.plainText(from: "Just text."), "Just text.")
    }
}
