import AppKit

// What a key press in the panel means.
enum KeyCommand: Equatable {
    case close          // esc
    case tab(Action)    // ⌘1 to ⌘4
    case copy           // ⌘C
    case none           // not one of ours; let the key through

    static func from(keyCode: UInt16, characters: String?, modifiers: NSEvent.ModifierFlags) -> KeyCommand {
        // Look only at the real modifier keys. Flags such as Caps Lock are ignored,
        // so shortcuts also work while Caps Lock is on.
        let held = modifiers.intersection([.command, .option, .control, .shift])
        let key = (characters ?? "").lowercased()

        if keyCode == 53 { return .close }   // 53 is the esc key
        guard held == .command else { return .none }

        if let number = Int(key), let tab = Action(rawValue: number - 1) {
            return .tab(tab)
        }
        if key == "c" { return .copy }
        return .none
    }
}
