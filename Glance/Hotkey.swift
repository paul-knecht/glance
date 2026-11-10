import Carbon.HIToolbox

// Registers the global hotkey ⌃⌥Space with macOS and calls `onPress`
// whenever it is pressed, no matter which app is in front.
//
// This uses an old but still supported system service (Carbon hotkeys).
// Its advantages: it needs no permission, and the key press does not also
// reach the other app (no stray space is typed).
final class Hotkey {

    // True if macOS accepted the hotkey.
    private(set) var isRegistered = false

    private let onPress: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init(onPress: @escaping () -> Void) {
        self.onPress = onPress

        // Tell macOS which function to call for "a hotkey was pressed" events.
        // The function gets a pointer to this object so it can find `onPress`.
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let pointerToSelf = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            if let userData {
                Unmanaged<Hotkey>.fromOpaque(userData).takeUnretainedValue().onPress()
            }
            return noErr
        }, 1, &eventType, pointerToSelf, &handlerRef)

        // Register Control + Option + Space. The id is just a name for our hotkey.
        let id = EventHotKeyID(signature: OSType(0x474C_4E43), id: 1)  // "GLNC"
        let status = RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey),
                                         id, GetApplicationEventTarget(), 0, &hotKeyRef)
        isRegistered = (status == noErr)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
