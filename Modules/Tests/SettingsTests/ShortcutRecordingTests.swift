import BouncerFoundation
import Carbon.HIToolbox
import Settings
import Testing

@Suite struct ShortcutRecordingTests {
    private let command: UInt = 1 << 20
    private let shift: UInt = 1 << 17

    @Test func keepsModifiers() {
        let shortcut = HotKey.Shortcut.recorded(keyCode: UInt16(kVK_ANSI_W), flags: command | shift)
        #expect(shortcut?.name == "⌘⇧W")
    }

    @Test func takesAFunctionKeyAlone() {
        #expect(HotKey.Shortcut.recorded(keyCode: UInt16(kVK_F3), flags: 0)?.name == "F3")
    }

    @Test func refusesALetterAlone() {
        #expect(HotKey.Shortcut.recorded(keyCode: UInt16(kVK_ANSI_W), flags: 0) == nil)
        #expect(HotKey.Shortcut.recorded(keyCode: UInt16(kVK_ANSI_W), flags: shift) == nil)
    }

    @Test func recordsTheDecksDefault() {
        let shortcut = HotKey.Shortcut.recorded(keyCode: UInt16(kVK_Escape), flags: command)
        #expect(shortcut == Preferences.defaultDecksShortcut)
        #expect(shortcut?.name == "⌘⎋")
    }

    @Test func cancelsOnlyOnEscapeAlone() {
        let escape = UInt16(kVK_Escape)
        let capsLock: UInt = 1 << 16
        #expect(HotKey.Shortcut.cancelsRecording(keyCode: escape, flags: 0))
        #expect(HotKey.Shortcut.cancelsRecording(keyCode: escape, flags: capsLock))
        #expect(!HotKey.Shortcut.cancelsRecording(keyCode: escape, flags: command))
        #expect(!HotKey.Shortcut.cancelsRecording(keyCode: UInt16(kVK_ANSI_W), flags: 0))
    }

    @Test func refusesAModifierKey() {
        #expect(HotKey.Shortcut.recorded(keyCode: UInt16(kVK_Command), flags: command) == nil)
    }
}
