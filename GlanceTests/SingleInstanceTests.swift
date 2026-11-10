import XCTest
@testable import Glance

// Two copies of Glance running at once both answer the hotkey and show two
// panels on top of each other. A newly started copy therefore asks the
// older ones to quit.
final class SingleInstanceTests: XCTestCase {

    func testNewCopyQuitsAllOlderCopies() {
        let others = SingleInstance.copiesToQuit(running: [100, 200, 300], own: 200, isRunningTests: false)
        XCTAssertEqual(others, [100, 300])
    }

    func testAloneQuitsNobody() {
        XCTAssertEqual(SingleInstance.copiesToQuit(running: [200], own: 200, isRunningTests: false), [])
    }

    // The tests start their own copy of the app. It must not quit the installed one.
    func testTestRunsQuitNobody() {
        XCTAssertEqual(SingleInstance.copiesToQuit(running: [100, 200], own: 200, isRunningTests: true), [])
    }
}
