import Foundation
import Hotkeys

/// What should collapse the menu bar again after it has been revealed.
public enum AutoRehide: Codable, Hashable, Sendable {
    case never
    case afterDelay(seconds: TimeInterval)
    case onFocusedAppChange
}

/// The complete user-facing configuration. One value type so it round-trips as a
/// single encode/decode and comparing two states is a plain `==`.
public struct Preferences: Codable, Hashable, Sendable {
    public var revealHotkey: KeyCombo?
    public var revealAlwaysHiddenHotkey: KeyCombo?
    public var autoRehide: AutoRehide
    public var enableAlwaysHiddenSection: Bool
    /// Reveal by moving the pointer into the menu bar, without a click.
    public var revealOnHover: Bool
    public var showBouncerIcon: Bool

    public init(
        revealHotkey: KeyCombo? = nil,
        revealAlwaysHiddenHotkey: KeyCombo? = nil,
        autoRehide: AutoRehide = .afterDelay(seconds: 10),
        enableAlwaysHiddenSection: Bool = false,
        revealOnHover: Bool = false,
        showBouncerIcon: Bool = true
    ) {
        self.revealHotkey = revealHotkey
        self.revealAlwaysHiddenHotkey = revealAlwaysHiddenHotkey
        self.autoRehide = autoRehide
        self.enableAlwaysHiddenSection = enableAlwaysHiddenSection
        self.revealOnHover = revealOnHover
        self.showBouncerIcon = showBouncerIcon
    }
}
