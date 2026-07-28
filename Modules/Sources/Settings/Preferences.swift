import Foundation

/// What should collapse the menu bar again after it has been revealed.
public enum AutoRehide: Codable, Hashable, Sendable {
    case never
    case afterDelay(seconds: TimeInterval)
    case onFocusedAppChange
}

/// The complete user-facing configuration. One value type so it round-trips as a
/// single encode/decode and comparing two states is a plain `==`.
public struct Preferences: Codable, Hashable, Sendable {
    public var autoRehide: AutoRehide
    public var enableAlwaysHiddenSection: Bool
    /// Reveal by moving the pointer into the menu bar, without a click.
    public var revealOnHover: Bool
    public var showBouncerIcon: Bool
    /// Show the hidden section as replicas in a bar of Bouncer's own, rather than by
    /// revealing it in the menu bar.
    ///
    /// Off by default and the only feature that asks for permissions: it needs Screen
    /// Recording to read the items, and Accessibility to pass clicks back to them.
    public var showItemsInBar: Bool

    public init(
        autoRehide: AutoRehide = .afterDelay(seconds: 10),
        enableAlwaysHiddenSection: Bool = false,
        revealOnHover: Bool = false,
        showBouncerIcon: Bool = true,
        showItemsInBar: Bool = false
    ) {
        self.autoRehide = autoRehide
        self.enableAlwaysHiddenSection = enableAlwaysHiddenSection
        self.revealOnHover = revealOnHover
        self.showBouncerIcon = showBouncerIcon
        self.showItemsInBar = showItemsInBar
    }
}
