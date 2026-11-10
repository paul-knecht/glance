import AppKit
import ApplicationServices
import Carbon.HIToolbox

// Finds out what text is selected in the app in front.
//
// It tries two ways, both of which need the Accessibility permission:
// 1. Ask the other app directly ("what is selected in your focused field?").
// 2. If the app doesn't answer, press ⌘C for the user, read the clipboard,
//    and put the old clipboard contents back.
enum SelectionReader {

    static var hasPermission: Bool {
        AXIsProcessTrusted()
    }

    // Asks macOS to add Glance to the Accessibility list (macOS shows its own
    // dialog the first time) and opens that page in System Settings.
    static func openPermissionSettings() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)

        let address = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: address) {
            NSWorkspace.shared.open(url)
        }
    }

    // Returns the selection, or nil if nothing (or only blank space) is selected.
    @MainActor
    static func read() async -> Selection? {
        // The primary screen's height is needed to convert coordinates below.
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0

        // Way 1 runs in the background so a slow app cannot freeze Glance.
        let (selection, outcome) = await Task.detached { readDirectly(screenHeight: screenHeight) }.value
        switch outcome {
        case .found: return selection
        case .nothingSelected: return nil
        case .unknown: break
        }

        // Way 2.
        let text = await copySelection(
            pasteboard: .general,
            modifiersReleased: { NSEvent.modifierFlags.intersection([.control, .option, .shift]).isEmpty },
            pressCopy: pressCommandC)
        guard let text else { return nil }
        let copied = Selection(text: text, context: nil, anchor: nil)
        return copied.text.isEmpty ? nil : copied
    }

    // What asking the other app told us.
    enum DirectOutcome: Equatable {
        case found             // it gave us the selected text
        case nothingSelected   // a text field told us nothing is selected: believe it
        case unknown           // no usable answer: try copying instead
    }

    // Decides what an app's answer means. `selectedText` is nil if the app
    // did not answer; `role` is the kind of element that has the keyboard.
    static func outcome(selectedText: String?, role: String?) -> DirectOutcome {
        guard let selectedText else { return .unknown }
        if !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .found }
        // Only real text fields are trusted when they say "nothing selected".
        // Other elements often say that simply because they don't know, and
        // pressing ⌘C in a text field with nothing selected would just beep.
        let textRoles = [kAXTextFieldRole as String, kAXTextAreaRole as String]
        return textRoles.contains(role ?? "") ? .nothingSelected : .unknown
    }

    // MARK: - Way 1: ask the other app

    private static func readDirectly(screenHeight: CGFloat) -> (Selection?, DirectOutcome) {
        let system = AXUIElementCreateSystemWide()
        // Never wait longer than a second for another app to answer.
        AXUIElementSetMessagingTimeout(system, 1.0)

        guard let focused = attribute(kAXFocusedUIElementAttribute, of: system),
              CFGetTypeID(focused) == AXUIElementGetTypeID() else { return (nil, .unknown) }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 1.0)

        let selectedText = attribute(kAXSelectedTextAttribute, of: element) as? String
        let role = attribute(kAXRoleAttribute, of: element) as? String
        let outcome = outcome(selectedText: selectedText, role: role)
        guard outcome == .found, let text = selectedText else { return (nil, outcome) }

        // Optional extras: where the selection is, and the sentence around it.
        var anchor: CGRect?
        var context: String?
        if let rangeValue = attribute(kAXSelectedTextRangeAttribute, of: element),
           let range = cfRange(from: rangeValue) {
            anchor = bounds(of: rangeValue, in: element, screenHeight: screenHeight)
            if Selection(text: text, context: nil, anchor: nil).isWord {
                context = sentence(around: range, in: element)
            }
        }
        return (Selection(text: text, context: context, anchor: anchor), .found)
    }

    // Reads one piece of information ("attribute") from an element of another app.
    private static func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    // Unpacks a text range (position and length, counted in UTF-16 units).
    private static func cfRange(from value: CFTypeRef) -> CFRange? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range
    }

    // Asks where on screen a range of text is. Accessibility measures from the
    // top-left of the primary screen; AppKit from the bottom-left, so we flip y.
    private static func bounds(of rangeValue: CFTypeRef, in element: AXUIElement, screenHeight: CGFloat) -> CGRect? {
        var value: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &value)
        guard result == .success, let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect),
              rect.width > 0, rect.height > 0, screenHeight > 0 else { return nil }
        return CGRect(x: rect.minX, y: screenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    // Reads up to 300 characters on each side of the selection and cuts out
    // the sentence that contains it.
    private static func sentence(around range: CFRange, in element: AXUIElement) -> String? {
        guard let total = attribute(kAXNumberOfCharactersAttribute, of: element) as? Int else { return nil }

        let start = max(0, range.location - 300)
        let end = min(total, range.location + range.length + 300)
        guard start <= range.location, range.location + range.length <= end else { return nil }

        var wide = CFRange(location: start, length: end - start)
        guard let wideValue = AXValueCreate(.cfRange, &wide) else { return nil }
        var value: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element, kAXStringForRangeParameterizedAttribute as CFString, wideValue, &value)
        guard result == .success, let text = value as? String else { return nil }

        // Find the selection inside the wider text. Positions are UTF-16 offsets.
        let offset = range.location - start
        guard offset + range.length <= text.utf16.count else { return nil }
        let lower = String.Index(utf16Offset: offset, in: text)
        let upper = String.Index(utf16Offset: offset + range.length, in: text)
        return SentenceFinder.sentence(in: text, around: lower..<upper)
    }

    // MARK: - Way 2: copy and read the clipboard

    // Set when an app had not copied by the time we gave up. The task keeps
    // watching the clipboard a little longer and undoes a late copy.
    @MainActor static var lateRestore: Task<Void, Never>?

    // Presses ⌘C (through `pressCopy`), reads what lands on the clipboard and
    // puts the old contents back. The pieces are passed in so tests can use
    // a private clipboard and a pretend app.
    @MainActor
    static func copySelection(pasteboard: NSPasteboard,
                              modifiersReleased: () -> Bool,
                              pressCopy: () -> Void) async -> String? {
        // Remember everything on the clipboard so we can put it back.
        let saved = contents(of: pasteboard)
        let countBefore = pasteboard.changeCount

        // The user is still holding Control and Option from the hotkey. Wait
        // until they let go; otherwise the app would see ⌃⌥⌘C, not ⌘C.
        var released = false
        for _ in 0..<30 {
            if modifiersReleased() {
                released = true
                break
            }
            await pause(milliseconds: 20)
        }
        guard released else { return nil }

        pressCopy()

        // Give the app up to 0.6 seconds to put the selection on the clipboard.
        for _ in 0..<30 {
            await pause(milliseconds: 20)
            if pasteboard.changeCount != countBefore {
                // Some apps empty the clipboard first and fill it a moment later.
                await pause(milliseconds: 20)
                let text = pasteboard.string(forType: .string)
                restore(saved, to: pasteboard)
                return text
            }
        }

        // The app has not copied (yet). Keep watching for 1.5 seconds so that
        // a slow copy does not replace what the user had on the clipboard.
        lateRestore = Task { @MainActor in
            for _ in 0..<30 {
                await pause(milliseconds: 50)
                if pasteboard.changeCount != countBefore {
                    await pause(milliseconds: 20)
                    restore(saved, to: pasteboard)
                    return
                }
            }
        }
        return nil
    }

    private typealias SavedClipboard = [[(NSPasteboard.PasteboardType, Data)]]

    // Everything on the clipboard: each item with all its kinds of data.
    @MainActor
    private static func contents(of pasteboard: NSPasteboard) -> SavedClipboard {
        (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
    }

    @MainActor
    private static func restore(_ saved: SavedClipboard, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let items = saved.map { entries -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entries { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }

    private static func pause(milliseconds: UInt64) async {
        try? await Task.sleep(nanoseconds: milliseconds * 1_000_000)
    }

    // Sends the key press ⌘C to the app in front.
    private static func pressCommandC() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyC = CGKeyCode(kVK_ANSI_C)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
