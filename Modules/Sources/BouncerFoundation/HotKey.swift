import Carbon.HIToolbox

/// A key combination, system-wide, for as long as it exists.
///
/// A hot key registered with the system is delivered to Bouncer instead of the frontmost app, so
/// while it exists that app no longer gets the combination: Chrome's bookmarks bar toggle for ⌘⇧B,
/// a new folder in Finder for ⌘⇧N. It needs no permission, unlike watching the keyboard for it would.
@MainActor
public final class HotKey {
    /// A key and the modifiers held with it, in Carbon's terms, which is what registering takes.
    public struct Shortcut: Codable, Hashable, Sendable {
        public var keyCode: UInt32
        public var modifiers: UInt32

        public init(keyCode: Int, modifiers: Int = 0) {
            self.keyCode = UInt32(keyCode)
            self.modifiers = UInt32(modifiers)
        }

        public static let commandShift = cmdKey | shiftKey

        /// The shortcut a key press makes, given its AppKit modifier flags; `nil` for a key alone other
        /// than a function key, which would take that key from every app, and for a modifier key itself.
        public static func recorded(keyCode: UInt16, flags: UInt) -> Shortcut? {
            // Typed out: CI's older compiler times out inferring the tuple types.
            let flagKeys: [(UInt, Int)] = [
                (1 << 20, cmdKey), (1 << 19, optionKey), (1 << 18, controlKey), (1 << 17, shiftKey)
            ]
            let modifiers = flagKeys.filter { flags & $0.0 != 0 }.map(\.1).reduce(0, |)
            let modifierKeys = [
                kVK_Command, kVK_RightCommand, kVK_Shift, kVK_RightShift, kVK_Option, kVK_RightOption,
                kVK_Control, kVK_RightControl, kVK_CapsLock, kVK_Function
            ]
            guard !modifierKeys.contains(Int(keyCode)) else { return nil }
            let shortcut = Shortcut(keyCode: Int(keyCode), modifiers: modifiers)
            let isFunctionKey = keyName(UInt32(keyCode)).hasPrefix("F") && keyName(UInt32(keyCode)).count > 1
            guard modifiers & ~shiftKey != 0 || isFunctionKey else { return nil }
            return shortcut
        }

        /// As Bouncer writes its shortcuts elsewhere, ⌃⌥⌘⇧ first: "⌘⇧B", "F3".
        public var name: String {
            let symbols: [(Int, String)] = [(controlKey, "⌃"), (optionKey, "⌥"), (cmdKey, "⌘"), (shiftKey, "⇧")]
            return symbols.filter { modifiers & UInt32($0.0) != 0 }.map(\.1).joined() + Self.keyName(keyCode)
        }

        /// Named keys by their code; any other key is the character it types on a US layout.
        static func keyName(_ code: UInt32) -> String {
            if let name = named[Int(code)] { return name }
            return characters[Int(code)] ?? "Key \(code)"
        }

        private static let named: [Int: String] = {
            let functionKeys = [
                kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20
            ]
            var names = Dictionary(
                uniqueKeysWithValues: functionKeys.enumerated().map { ($0.element, "F\($0.offset + 1)") }
            )
            names.merge([
                kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
                kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋", kVK_Delete: "⌫",
                kVK_ForwardDelete: "⌦", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟"
            ]) { $1 }
            return names
        }()

        private static let characters: [Int: String] = {
            let codes = [
                kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E, kVK_ANSI_F, kVK_ANSI_G,
                kVK_ANSI_H, kVK_ANSI_I, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_M, kVK_ANSI_N,
                kVK_ANSI_O, kVK_ANSI_P, kVK_ANSI_Q, kVK_ANSI_R, kVK_ANSI_S, kVK_ANSI_T, kVK_ANSI_U,
                kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X, kVK_ANSI_Y, kVK_ANSI_Z,
                kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4,
                kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9,
                kVK_ANSI_Minus, kVK_ANSI_Equal, kVK_ANSI_LeftBracket, kVK_ANSI_RightBracket,
                kVK_ANSI_Semicolon, kVK_ANSI_Quote, kVK_ANSI_Comma, kVK_ANSI_Period, kVK_ANSI_Slash,
                kVK_ANSI_Backslash, kVK_ANSI_Grave
            ]
            let typed = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-=[];',./\\`").map(String.init)
            return Dictionary(uniqueKeysWithValues: zip(codes, typed))
        }()
    }

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let id: UInt32
    private let action: @MainActor () -> Void

    /// - Parameter id: tells this hot key's presses from every other's; unique among those registered.
    public init?(_ shortcut: Shortcut, id: UInt32, action: @MainActor @escaping () -> Void) {
        self.id = id
        self.action = action
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                let hotKey = Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue()
                var pressed = EventHotKeyID()
                let read = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &pressed
                )
                // Every hot key's handler hears every press; the others are passed on to theirs.
                guard read == noErr, pressed.signature == HotKey.signature, pressed.id == hotKey.id else {
                    return OSStatus(eventNotHandledErr)
                }
                // Carbon delivers application events on the main thread.
                MainActor.assumeIsolated { hotKey.action() }
                return noErr
            },
            1, &pressed, Unmanaged.passUnretained(self).toOpaque(), &handler
        )
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let registered = RegisterEventHotKey(
            shortcut.keyCode, shortcut.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKey
        )
        guard installed == noErr, registered == noErr else {
            Log.app.error("""
                Registering \(shortcut.name, privacy: .public) failed: \
                \(installed, privacy: .public) \(registered, privacy: .public)
                """)
            unregister()
            return nil
        }
    }

    /// Hands the combination back to the apps.
    public func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
    }

    nonisolated private static let signature = OSType(0x424E_4352) // "BNCR"
}
