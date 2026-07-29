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
    /// Slide that bar out of the menu bar and back into it, rather than having it appear at
    /// once.
    public var animateBar: Bool
    /// How long that slide takes, in seconds.
    public var barAnimationDuration: TimeInterval

    public init(
        autoRehide: AutoRehide = .afterDelay(seconds: 10),
        enableAlwaysHiddenSection: Bool = false,
        revealOnHover: Bool = false,
        showBouncerIcon: Bool = true,
        showItemsInBar: Bool = false,
        animateBar: Bool = true,
        barAnimationDuration: TimeInterval = 0.18
    ) {
        self.autoRehide = autoRehide
        self.enableAlwaysHiddenSection = enableAlwaysHiddenSection
        self.revealOnHover = revealOnHover
        self.showBouncerIcon = showBouncerIcon
        self.showItemsInBar = showItemsInBar
        self.animateBar = animateBar
        self.barAnimationDuration = barAnimationDuration
    }

    /// A blob stored before a key existed must keep the user's other settings, not throw
    /// them away — so every key added after 0.1.0 decodes as optional with its default.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        autoRehide = try container.decode(AutoRehide.self, forKey: .autoRehide)
        enableAlwaysHiddenSection = try container.decode(Bool.self, forKey: .enableAlwaysHiddenSection)
        revealOnHover = try container.decode(Bool.self, forKey: .revealOnHover)
        showBouncerIcon = try container.decode(Bool.self, forKey: .showBouncerIcon)
        showItemsInBar = try container.decodeIfPresent(Bool.self, forKey: .showItemsInBar) ?? false
        animateBar = try container.decodeIfPresent(Bool.self, forKey: .animateBar) ?? true
        barAnimationDuration =
            try container.decodeIfPresent(TimeInterval.self, forKey: .barAnimationDuration) ?? 0.18
    }
}
