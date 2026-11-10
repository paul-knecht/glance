import AppKit

// The floating window that holds the panel.
//
// It is a "non-activating panel": it can take keyboard input without Glance
// becoming the active app. That way the other app stays in front and its
// selection stays highlighted, like with Spotlight.
final class PanelWindow: NSPanel {

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 380, height: 260),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        // The SwiftUI view draws its own rounded background.
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        // Show on whatever Space (desktop) the user is on, also over full-screen apps.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    // Without this a borderless window refuses keyboard input.
    override var canBecomeKey: Bool { true }
}
