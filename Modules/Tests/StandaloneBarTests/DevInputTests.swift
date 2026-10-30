#if DEV
import Carbon.HIToolbox
import CoreGraphics
@testable import StandaloneBar
import Testing

struct DevInputTests {
    @Test func readsModifiersAndKey() {
        let shortcut = DevInput.shortcut("cmd+shift+n")
        #expect(shortcut == .init(keyCode: CGKeyCode(kVK_ANSI_N), flags: [.maskCommand, .maskShift]))
        #expect(DevInput.shortcut("Escape") == .init(keyCode: CGKeyCode(kVK_Escape), flags: []))
    }

    @Test func typesWithTheKeysOfAUSLayout() {
        #expect(DevInput.shortcut(typing: "H") == .init(keyCode: CGKeyCode(kVK_ANSI_H), flags: .maskShift))
        #expect(DevInput.shortcut(typing: "1") == .init(keyCode: CGKeyCode(kVK_ANSI_1), flags: []))
        #expect(DevInput.shortcut(typing: "?") == .init(keyCode: CGKeyCode(kVK_ANSI_Slash), flags: .maskShift))
        #expect(DevInput.shortcut(typing: "`") == .init(keyCode: CGKeyCode(kVK_ANSI_Grave), flags: []))
        #expect(DevInput.shortcut(typing: "ü") == nil)
    }

    @Test func refusesWhatItCannotPress() {
        #expect(DevInput.shortcut("cmd+f13") == nil)
        #expect(DevInput.shortcut("hyper+a") == nil)
        #expect(DevInput.shortcut("") == nil)
    }
}
#endif
