import Foundation

// Works out where the panel goes. All values use AppKit coordinates:
// the origin is the bottom-left corner of the screen and y grows upwards.
enum PanelPlacement {

    // Gap between the selection and the panel.
    static let gap: CGFloat = 6

    // Distance the panel keeps from the screen's edges.
    static let margin: CGFloat = 8

    // Returns the panel's bottom-left corner.
    // The panel goes just below the selection (`anchor`), or below the mouse
    // pointer if we don't know where the selection is.
    static func origin(anchor: CGRect?, mouse: CGPoint, panelSize: CGSize, screen: CGRect) -> CGPoint {
        // The rectangle we place the panel next to. For the mouse it has no size.
        let target = anchor ?? CGRect(origin: mouse, size: .zero)

        var x = target.minX
        var y = target.minY - gap - panelSize.height

        // No room below? Put the panel above instead.
        if y < screen.minY + margin {
            y = target.maxY + gap
        }

        // Keep the whole panel on screen. The top edge wins if it cannot fit.
        x = min(max(x, screen.minX + margin), screen.maxX - margin - panelSize.width)
        y = max(y, screen.minY + margin)
        y = min(y, screen.maxY - margin - panelSize.height)

        return CGPoint(x: x, y: y)
    }

    // The panel's new frame when its content needs a different height.
    // The top edge stays where it is, so the panel grows downwards.
    static func resized(_ frame: CGRect, toHeight height: CGFloat, visible: CGRect) -> CGRect {
        var result = frame
        result.size.height = height
        result.origin.y = frame.maxY - height

        // Keep the bottom on screen, but never at the cost of the top:
        // the tab bar must stay visible.
        result.origin.y = max(result.origin.y, visible.minY + margin)
        result.origin.y = min(result.origin.y, visible.maxY - margin - height)
        return result
    }
}
