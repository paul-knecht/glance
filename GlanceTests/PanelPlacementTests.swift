import XCTest
@testable import Glance

// Checks where the panel is put on screen. Coordinates are AppKit's:
// the origin is the bottom-left corner and y grows upwards.
final class PanelPlacementTests: XCTestCase {

    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let size = CGSize(width: 380, height: 300)

    func testBelowAnchor() {
        let anchor = CGRect(x: 500, y: 600, width: 80, height: 18)
        let origin = PanelPlacement.origin(anchor: anchor, mouse: .zero, panelSize: size, screen: screen)
        XCTAssertEqual(origin.x, 500)
        XCTAssertEqual(origin.y, 600 - 6 - 300)
    }

    func testAboveAnchorWhenNoRoomBelow() {
        let anchor = CGRect(x: 500, y: 100, width: 80, height: 18)
        let origin = PanelPlacement.origin(anchor: anchor, mouse: .zero, panelSize: size, screen: screen)
        XCTAssertEqual(origin.y, 118 + 6)
    }

    func testClampedAtRightEdge() {
        let anchor = CGRect(x: 1400, y: 600, width: 30, height: 18)
        let origin = PanelPlacement.origin(anchor: anchor, mouse: .zero, panelSize: size, screen: screen)
        XCTAssertEqual(origin.x, 1440 - 8 - 380)
    }

    func testUsesMouseWithoutAnchor() {
        let origin = PanelPlacement.origin(anchor: nil, mouse: CGPoint(x: 300, y: 700), panelSize: size, screen: screen)
        XCTAssertEqual(origin.x, 300)
        XCTAssertEqual(origin.y, 700 - 6 - 300)
    }

    func testStaysInsideSecondScreen() {
        let second = CGRect(x: 1440, y: -200, width: 1920, height: 1080)
        let origin = PanelPlacement.origin(anchor: nil, mouse: CGPoint(x: 1445, y: 870), panelSize: size, screen: second)
        XCTAssertEqual(origin.x, 1440 + 8)
        XCTAssertEqual(origin.y, 870 - 6 - 300)
        let low = PanelPlacement.origin(anchor: nil, mouse: CGPoint(x: 2000, y: -150), panelSize: size, screen: second)
        XCTAssertGreaterThanOrEqual(low.y, -200 + 8)
        XCTAssertLessThanOrEqual(low.y + 300, 880 - 8)
    }

    func testPanelTallerThanScreenStillStartsAtTopMargin() {
        let tiny = CGRect(x: 0, y: 0, width: 400, height: 200)
        let origin = PanelPlacement.origin(anchor: nil, mouse: CGPoint(x: 10, y: 100), panelSize: size, screen: tiny)
        // The top edge is kept visible; the bottom may hang off.
        XCTAssertEqual(origin.y + 300, 200 - 8)
    }
}
