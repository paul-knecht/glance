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

        // Way 1 runs in the background so a slow app cannot freeze our menu bar icon.
        let direct = await Task.detached { readDirectly(screenHeight: screenHeight) }.value
        if let direct { return direct }

        // Way 2.
        guard let text = await readByCopying() else { return nil }
        let selection = Selection(text: text, context: nil, anchor: nil)
        return selection.text.isEmpty ? nil : selection
    }

    // MARK: - Way 1: ask the other app

    private static func readDirectly(screenHeight: CGFloat) -> Selection? {
        let system = AXUIElementCreateSystemWide()
        // Never wait longer than a second for another app to answer.
        AXUIElementSetMessagingTimeout(system, 1.0)

        guard let focused = attribute(kAXFocusedUIElementAttribute, of: system),
              CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 1.0)

        guard let text = attribute(kAXSelectedTextAttribute, of: element) as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

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
        return Selection(text: text, context: context, anchor: anchor)
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

    @MainActor
    private static func readByCopying() async -> String? {
        let pasteboard = NSPasteboard.general

        // Remember everything on the clipboard so we can put it back.
        let saved: [[(NSPasteboard.PasteboardType, Data)]] = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        let countBefore = pasteboard.changeCount

        // The user is still holding Control and Option from the hotkey. Wait
        // until they let go; otherwise the app would see ⌃⌥⌘C, not ⌘C.
        var released = false
        for _ in 0..<30 {
            if NSEvent.modifierFlags.intersection([.control, .option, .shift]).isEmpty {
                released = true
                break
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        guard released else { return nil }

        pressCommandC()

        // Give the app up to 0.4 seconds to put the selection on the clipboard.
        var text: String?
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 20_000_000)
            if pasteboard.changeCount != countBefore {
                text = pasteboard.string(forType: .string)
                break
            }
        }

        // Put the old contents back, whatever happened.
        if pasteboard.changeCount != countBefore {
            pasteboard.clearContents()
            let items = saved.map { entries -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in entries { item.setData(data, forType: type) }
                return item
            }
            if !items.isEmpty { pasteboard.writeObjects(items) }
        }
        return text
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
