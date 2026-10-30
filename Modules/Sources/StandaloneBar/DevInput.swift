#if DEV
import AppKit
import Carbon.HIToolbox

/// Keys, text and clicks for `DevHarness`, posted as real input events so they take the path a
/// person's would: through hot keys, focus and the key window.
enum DevInput {
    struct Shortcut: Equatable {
        let keyCode: CGKeyCode
        let flags: CGEventFlags
    }

    /// `cmd+shift+n`, `escape`, `cmd+z`: modifiers then one key, joined by `+`. Letters are where
    /// a US layout has them.
    static func shortcut(_ spec: String) -> Shortcut? {
        var parts = spec.lowercased().split(separator: "+").map(String.init)
        guard let key = parts.popLast(), let code = keyCodes[key] else { return nil }
        var flags: CGEventFlags = []
        for part in parts {
            guard let flag = modifiers[part] else { return nil }
            flags.insert(flag)
        }
        return Shortcut(keyCode: code, flags: flags)
    }

    static func press(_ shortcut: Shortcut) async {
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: shortcut.keyCode, keyDown: isDown)
            event?.flags = shortcut.flags
            event?.post(tap: .cghidEventTap)
            await pause()
        }
    }

    /// Presses the keys a US layout types `text` with. A character no key types arrives as text on
    /// the event, which a text field does not reliably take.
    static func type(_ text: String) async {
        for character in text {
            if let shortcut = shortcut(typing: character) {
                await press(shortcut)
                continue
            }
            let units = Array(String(character).utf16)
            for isDown in [true, false] {
                let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: isDown)
                event?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                event?.post(tap: .cghidEventTap)
                await pause()
            }
        }
    }

    static func shortcut(typing character: Character) -> Shortcut? {
        if character == " " { return Shortcut(keyCode: CGKeyCode(kVK_Space), flags: []) }
        if character == "\n" { return Shortcut(keyCode: CGKeyCode(kVK_Return), flags: []) }
        if character.isLetter, character.isASCII, let code = keyCodes[character.lowercased()] {
            return Shortcut(keyCode: code, flags: character.isUppercase ? .maskShift : [])
        }
        if let index = unshifted.firstIndex(of: character) {
            return Shortcut(keyCode: CGKeyCode(symbolKeys[index]), flags: [])
        }
        if let index = shifted.firstIndex(of: character) {
            return Shortcut(keyCode: CGKeyCode(symbolKeys[index]), flags: .maskShift)
        }
        return nil
    }

    /// A left click at `point`, in the window server's coordinates: the ones `dump` prints.
    static func tap(at point: CGPoint) async {
        for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
                .post(tap: .cghidEventTap)
            await pause()
        }
    }

    /// Long enough for the app to take each event before the next.
    private static func pause() async {
        try? await Task.sleep(for: .milliseconds(15))
    }

    private static let modifiers: [String: CGEventFlags] = [
        "cmd": .maskCommand, "shift": .maskShift, "opt": .maskAlternate, "alt": .maskAlternate,
        "ctrl": .maskControl
    ]

    /// The digit and symbol keys, and what each types without and with Shift.
    private static let symbolKeys: [Int] = [
        kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8,
        kVK_ANSI_9, kVK_ANSI_0, kVK_ANSI_Minus, kVK_ANSI_Equal, kVK_ANSI_LeftBracket, kVK_ANSI_RightBracket,
        kVK_ANSI_Semicolon, kVK_ANSI_Quote, kVK_ANSI_Comma, kVK_ANSI_Period, kVK_ANSI_Slash,
        kVK_ANSI_Backslash, kVK_ANSI_Grave
    ]
    private static let unshifted = Array("1234567890-=[];',./\\`")
    private static let shifted = Array("!@#$%^&*()_+{}:\"<>?|~")

    private static let keyCodes: [String: CGKeyCode] = {
        var codes: [String: Int] = [
            "return": kVK_Return, "escape": kVK_Escape, "tab": kVK_Tab, "space": kVK_Space,
            "delete": kVK_Delete, "left": kVK_LeftArrow, "right": kVK_RightArrow,
            "up": kVK_UpArrow, "down": kVK_DownArrow
        ]
        let letters: [Int] = [
            kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E, kVK_ANSI_F, kVK_ANSI_G,
            kVK_ANSI_H, kVK_ANSI_I, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_M, kVK_ANSI_N,
            kVK_ANSI_O, kVK_ANSI_P, kVK_ANSI_Q, kVK_ANSI_R, kVK_ANSI_S, kVK_ANSI_T, kVK_ANSI_U,
            kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X, kVK_ANSI_Y, kVK_ANSI_Z
        ]
        for (letter, code) in zip("abcdefghijklmnopqrstuvwxyz", letters) { codes[String(letter)] = code }
        return codes.mapValues { CGKeyCode($0) }
    }()
}
#endif
