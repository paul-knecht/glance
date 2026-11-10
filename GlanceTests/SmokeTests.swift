import XCTest
@testable import Glance

// Checks that the app starts with our AppDelegate in charge.
final class SmokeTests: XCTestCase {

    func testAppDelegateExists() {
        XCTAssertTrue(NSApp.delegate is AppDelegate)
    }

    // ⌘V, ⌘C, ⌘X and ⌘A only work in text fields (like the API key field)
    // if the app has an Edit menu that carries those shortcuts.
    func testEditShortcutsExistSoPasteWorks() throws {
        let menus = NSApp.mainMenu?.items.compactMap(\.submenu) ?? []
        let keys = menus.flatMap(\.items).map(\.keyEquivalent)
        for key in ["x", "c", "v", "a"] {
            XCTAssertTrue(keys.contains(key), "No menu item with ⌘\(key.uppercased())")
        }
    }

    // The menu behind the menu bar icon offers the API key dialog and Quit.
    @MainActor
    func testStatusMenuHasKeyAndQuitItems() throws {
        let delegate = try XCTUnwrap(NSApp.delegate as? AppDelegate)
        let titles = delegate.statusItem.menu?.items.map(\.title) ?? []
        XCTAssertTrue(titles.contains("Set API key…"))
        XCTAssertTrue(titles.contains("Quit"))
    }
}
