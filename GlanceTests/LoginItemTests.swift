import XCTest
@testable import Glance

// Checks when Glance switches "start at login" on by itself.
final class LoginItemTests: XCTestCase {

    // Only an installed copy does it, and only the first time it runs.
    func testInstalledCopyEnablesItselfOnce() {
        XCTAssertTrue(LoginItem.shouldEnableAutomatically(bundlePath: "/Applications/Glance.app", alreadyDone: false))
        XCTAssertTrue(LoginItem.shouldEnableAutomatically(bundlePath: "/Users/someone/Applications/Glance.app", alreadyDone: false))
        XCTAssertFalse(LoginItem.shouldEnableAutomatically(bundlePath: "/Applications/Glance.app", alreadyDone: true))
    }

    // A copy in a build folder (Xcode, tests) must never add itself to the login items.
    func testBuildFolderCopyNeverEnablesItself() {
        let path = "/Users/someone/Developer/glance/build/Build/Products/Debug/Glance.app"
        XCTAssertFalse(LoginItem.shouldEnableAutomatically(bundlePath: path, alreadyDone: false))
    }
}
