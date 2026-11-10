import XCTest
@testable import Glance

// Tests for problems found in the review of the first version.
@MainActor
final class ReviewFixTests: XCTestCase {

    // MARK: - Resizing the panel

    private let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testResizeKeepsTopEdge() {
        let frame = CGRect(x: 100, y: 500, width: 380, height: 200)   // top at 700
        let result = PanelPlacement.resized(frame, toHeight: 300, visible: visible)
        XCTAssertEqual(result.maxY, 700)
        XCTAssertEqual(result.height, 300)
        XCTAssertEqual(result.minX, 100)
    }

    func testResizeMovesUpWhenBottomWouldLeaveScreen() {
        let frame = CGRect(x: 100, y: 50, width: 380, height: 100)    // top at 150
        let result = PanelPlacement.resized(frame, toHeight: 300, visible: visible)
        XCTAssertEqual(result.minY, 8)
    }

    // A panel taller than the screen must keep its top (the tab bar) visible.
    func testResizeNeverPushesTopOffScreen() {
        let small = CGRect(x: 0, y: 0, width: 1440, height: 400)
        let frame = CGRect(x: 100, y: 100, width: 380, height: 100)
        let result = PanelPlacement.resized(frame, toHeight: 600, visible: small)
        XCTAssertEqual(result.maxY, 400 - 8)
    }

    // MARK: - Keys

    func testEscCloses() {
        XCTAssertEqual(KeyCommand.from(keyCode: 53, characters: "\u{1b}", modifiers: []), .close)
    }

    func testCommandNumbersSelectTabs() {
        XCTAssertEqual(KeyCommand.from(keyCode: 18, characters: "1", modifiers: [.command]), .tab(.explain))
        XCTAssertEqual(KeyCommand.from(keyCode: 21, characters: "4", modifiers: [.command]), .tab(.rewrite))
        XCTAssertEqual(KeyCommand.from(keyCode: 23, characters: "5", modifiers: [.command]), .none)
        XCTAssertEqual(KeyCommand.from(keyCode: 18, characters: "1", modifiers: []), .none)
    }

    func testCommandCCopies() {
        XCTAssertEqual(KeyCommand.from(keyCode: 8, characters: "c", modifiers: [.command]), .copy)
        XCTAssertEqual(KeyCommand.from(keyCode: 8, characters: "c", modifiers: [.command, .shift]), .none)
        XCTAssertEqual(KeyCommand.from(keyCode: 8, characters: "c", modifiers: []), .none)
    }

    // Caps Lock (and other flags that are not real modifier keys) must not break shortcuts.
    func testCapsLockDoesNotBreakShortcuts() {
        XCTAssertEqual(KeyCommand.from(keyCode: 8, characters: "C", modifiers: [.command, .capsLock]), .copy)
        XCTAssertEqual(KeyCommand.from(keyCode: 18, characters: "1", modifiers: [.command, .capsLock, .numericPad]), .tab(.explain))
    }

    // MARK: - Asking the other app

    func testDirectOutcome() {
        XCTAssertEqual(SelectionReader.outcome(selectedText: "word", role: "AXTextArea"), .found)
        XCTAssertEqual(SelectionReader.outcome(selectedText: "word", role: nil), .found)
        // A text field that answers "nothing selected" is believed: no copying.
        XCTAssertEqual(SelectionReader.outcome(selectedText: "", role: "AXTextArea"), .nothingSelected)
        XCTAssertEqual(SelectionReader.outcome(selectedText: "  \n", role: "AXTextField"), .nothingSelected)
        // Anything else that answers "nothing" may just not know; try copying.
        XCTAssertEqual(SelectionReader.outcome(selectedText: "", role: "AXGroup"), .unknown)
        XCTAssertEqual(SelectionReader.outcome(selectedText: nil, role: "AXTextArea"), .unknown)
        XCTAssertEqual(SelectionReader.outcome(selectedText: nil, role: nil), .unknown)
    }

    // MARK: - Copy fallback and the clipboard

    private var pasteboard: NSPasteboard!
    private let custom = NSPasteboard.PasteboardType("local.glance.tests.custom")

    override func setUp() {
        // A private clipboard, so the tests never touch the real one.
        pasteboard = NSPasteboard(name: NSPasteboard.Name("local.glance.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("old text", forType: .string)
        pasteboard.setData(Data([1, 2, 3]), forType: custom)
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
    }

    private func assertClipboardIsAsBefore(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(pasteboard.string(forType: .string), "old text", file: file, line: line)
        XCTAssertEqual(pasteboard.data(forType: custom), Data([1, 2, 3]), file: file, line: line)
    }

    // Pretends to be the other app: puts `text` on the clipboard after a delay.
    private func appCopies(_ text: String, afterMilliseconds delay: UInt64) -> () -> Void {
        { [pasteboard] in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: delay * 1_000_000)
                pasteboard!.clearContents()
                pasteboard!.setString(text, forType: .string)
            }
        }
    }

    func testCopyReturnsTextAndRestoresClipboard() async {
        let text = await SelectionReader.copySelection(pasteboard: pasteboard, modifiersReleased: { true },
                                                       pressCopy: appCopies("selected", afterMilliseconds: 30))
        XCTAssertEqual(text, "selected")
        assertClipboardIsAsBefore()
    }

    func testAppThatNeverCopiesLeavesClipboardAlone() async {
        let countBefore = pasteboard.changeCount
        let text = await SelectionReader.copySelection(pasteboard: pasteboard, modifiersReleased: { true }, pressCopy: {})
        XCTAssertNil(text)
        XCTAssertEqual(pasteboard.changeCount, countBefore)
        assertClipboardIsAsBefore()
    }

    // An app that copies after we gave up must still not keep the clipboard.
    func testLateCopyIsStillUndone() async {
        let text = await SelectionReader.copySelection(pasteboard: pasteboard, modifiersReleased: { true },
                                                       pressCopy: appCopies("late", afterMilliseconds: 900))
        XCTAssertNil(text)
        await SelectionReader.lateRestore?.value
        assertClipboardIsAsBefore()
    }

    func testHeldModifiersMeanNoCopyAtAll() async {
        var pressed = false
        let text = await SelectionReader.copySelection(pasteboard: pasteboard, modifiersReleased: { false },
                                                       pressCopy: { pressed = true })
        XCTAssertNil(text)
        XCTAssertFalse(pressed)
        assertClipboardIsAsBefore()
    }

    // MARK: - Nothing on disk

    func testRequestsUseASessionThatStoresNothing() {
        XCTAssertNil(ClaudeClient.session.configuration.urlCache)
    }
}
