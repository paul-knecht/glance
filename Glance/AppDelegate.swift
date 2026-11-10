import AppKit
import SwiftUI

// Glance has no menu bar icon and no Dock icon. This object owns the
// hotkey, the floating panel and the settings window.
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    // Where the API key is kept.
    let keychain = KeychainStore()

    // The settings window, shown when the app is opened again while running.
    lazy var settingsWindow: NSWindow = {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "Glance"
        // Keep the window object alive after it is closed, so it can be shown again.
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(
            hotkeyAvailable: hotkey?.isRegistered ?? false,
            setAPIKey: { [weak self] in self?.setAPIKey() },
            quit: { NSApp.terminate(nil) }
        ))
        return window
    }()

    // The global hotkey ⌃⌥Space.
    var hotkey: Hotkey!

    // The floating window and what it shows. The model gets the real pieces
    // it needs: a way to read the API key, and the request to Claude.
    let panel = PanelWindow()
    lazy var model = PanelModel(
        loadKey: { [keychain] in keychain.load() },
        stream: { system, user, apiKey in
            ClaudeClient.stream(system: system, user: user, apiKey: apiKey)
        }
    )

    // True while we are reading the selection, so a second press is ignored.
    private var isReading = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Give the app an Edit menu. It is never visible (Glance has no menu bar
        // of its own), but macOS uses it to make ⌘X, ⌘C, ⌘V and ⌘A work in
        // text fields, for example when pasting the API key.
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = editMenu
        let mainMenu = NSMenu()
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu

        // Put the SwiftUI view into the floating window. When the view's
        // height changes, the window follows.
        let view = PanelView(model: model) { [weak self] height in
            self?.resizePanel(to: height)
        }
        let hostingView = NSHostingView(rootView: view)
        // We size the window ourselves (see resizePanel), so the view must not.
        hostingView.sizingOptions = []
        panel.contentView = hostingView

        // Listen for the hotkey.
        hotkey = Hotkey { [weak self] in
            // The hotkey always arrives on the main thread.
            MainActor.assumeIsolated { self?.hotkeyPressed() }
        }

        // The first time an installed copy runs, add it to the login items.
        let defaults = UserDefaults.standard
        if LoginItem.shouldEnableAutomatically(bundlePath: Bundle.main.bundlePath,
                                               alreadyDone: defaults.bool(forKey: "didSetUpLoginItem")) {
            LoginItem.setEnabled(true)
            defaults.set(true, forKey: "didSetUpLoginItem")
        }

        // Keys pressed while the panel has the keyboard: esc, ⌘1–⌘4, ⌘C.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isVisible, event.window === self.panel else { return event }
            // Returning nil means "handled, don't pass it on".
            return self.handleKey(event) ? nil : event
        }

        // Close the panel when the user clicks anywhere outside Glance.
        // (A "global monitor" hears clicks that go to other apps.)
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.closePanel() }
        }
    }

    // Called when the user opens Glance while it is already running
    // (from Applications, Spotlight or the Dock). We show the settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func showSettings() {
        // A background app has to step forward, or the window opens behind others.
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow.center()
        settingsWindow.makeKeyAndOrderFront(nil)
    }

    // MARK: - Panel

    // Called when ⌃⌥Space is pressed.
    func hotkeyPressed() {
        // While the panel is open, the hotkey closes it.
        if panel.isVisible {
            closePanel()
            return
        }
        guard !isReading else { return }
        isReading = true

        // Remember where the mouse is now, in case the app can't tell us
        // where the selection is.
        let mouse = NSEvent.mouseLocation
        let hasPermission = SelectionReader.hasPermission

        Task {
            let selection = hasPermission ? await SelectionReader.read() : nil
            isReading = false
            model.open(selection: selection, hasPermission: hasPermission)
            showPanel(anchor: selection?.anchor, mouse: mouse)
        }
    }

    // Places the panel near the selection (or the mouse) and shows it.
    private func showPanel(anchor: CGRect?, mouse: CGPoint) {
        // Use the screen the selection or the mouse is on.
        let point = anchor?.origin ?? mouse
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let origin = PanelPlacement.origin(anchor: anchor, mouse: mouse,
                                           panelSize: panel.frame.size, screen: visible)
        panel.setFrameOrigin(origin)

        // Show it and give it the keyboard, without making Glance the active app.
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func closePanel() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        model.close()
    }

    // Changes the window's height to fit its content. The top edge stays
    // where it is, so the panel grows downwards as the answer arrives.
    private func resizePanel(to height: CGFloat) {
        guard height > 0, abs(panel.frame.height - height) > 0.5,
              let visible = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else { return }
        panel.setFrame(PanelPlacement.resized(panel.frame, toHeight: height, visible: visible), display: true)
    }

    // Handles a key press in the panel. Returns true if the key was used.
    private func handleKey(_ event: NSEvent) -> Bool {
        let command = KeyCommand.from(keyCode: event.keyCode,
                                      characters: event.charactersIgnoringModifiers,
                                      modifiers: event.modifierFlags)
        switch command {
        case .close:
            closePanel()
            return true

        case .tab(let tab):
            model.select(tab)
            return true

        case .copy:
            // If text is selected in the question field, let ⌘C copy that as usual.
            if let editor = panel.firstResponder as? NSTextView, editor.selectedRange().length > 0 {
                return false
            }
            guard let text = model.textToCopy else { return true }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            model.noteCopied()
            return true

        case .none:
            return false
        }
    }

    // Shows a small dialog where the user types their Anthropic API key.
    // The field hides what is typed, and the key goes straight into the Keychain.
    @objc func setAPIKey() {
        let alert = NSAlert()
        alert.messageText = "Anthropic API key"
        alert.informativeText = "The key is stored in your Mac's Keychain. Leave the field empty and press Save to remove a stored key."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        // A menu-bar-only app has to step forward, or the dialog opens behind other windows.
        NSApp.activate(ignoringOtherApps: true)

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let key = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty {
            keychain.delete()
        } else {
            keychain.save(key)
        }
    }
}
