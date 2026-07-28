import AppKit
import Testing

@testable import StandaloneBar

@Suite("Modifier translation")
struct ModifierFlagsTests {
    @Test("Option survives the trip, because several items show a different menu for it")
    func option() {
        #expect(NSEvent.ModifierFlags.option.cgEventFlags == .maskAlternate)
    }

    @Test("Every modifier that changes what an item does is carried")
    func allModifiers() {
        let flags: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        let expected: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        #expect(flags.cgEventFlags == expected)
    }

    @Test("Modifiers that do not change the click are dropped")
    func ignoresIrrelevant() {
        // Caps lock and the function key arrive on ordinary clicks and mean nothing here;
        // passing them through would make an unmodified click look modified.
        let flags: NSEvent.ModifierFlags = [.capsLock, .function, .numericPad]
        #expect(flags.cgEventFlags == [])
    }

    @Test("No modifiers means no flags")
    func none() {
        #expect(NSEvent.ModifierFlags().cgEventFlags == [])
    }
}
