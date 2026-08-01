import Foundation

/// What should collapse the menu bar again after it has been revealed.
public enum AutoRehide: Codable, Hashable, Sendable {
    case never
    case afterDelay(seconds: TimeInterval)
    case onFocusedAppChange
}

/// How the standalone bar's panel is painted.
///
/// Plain values rather than a colour type, so the choice encodes with the rest of the
/// preferences and Settings stays free of AppKit. There is no opacity: the cover half of the
/// panel exists to hide icons, and anything short of opaque leaves them ghosting through.
public enum BarStyle: Codable, Hashable, Sendable {
    /// A grey that follows a light or dark menu bar.
    case automatic
    /// Liquid Glass, on a macOS that has it; the automatic grey where it does not.
    case glass
    /// A flat colour of the user's choosing, in sRGB.
    case custom(red: Double, green: Double, blue: Double)

    /// The greys `automatic` resolves to, as white levels rather than colours so Settings
    /// stays free of AppKit. Shared so the bar and the settings swatch cannot drift apart.
    public static let automaticLight = 0.88
    public static let automaticDark = 0.24
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
    /// What that bar's cover and shelf are painted with.
    public var barStyle: BarStyle

    public init(
        autoRehide: AutoRehide = .afterDelay(seconds: 10),
        enableAlwaysHiddenSection: Bool = false,
        revealOnHover: Bool = false,
        showBouncerIcon: Bool = true,
        showItemsInBar: Bool = false,
        animateBar: Bool = true,
        barAnimationDuration: TimeInterval = 0.18,
        barStyle: BarStyle = .automatic
    ) {
        self.autoRehide = autoRehide
        self.enableAlwaysHiddenSection = enableAlwaysHiddenSection
        self.revealOnHover = revealOnHover
        self.showBouncerIcon = showBouncerIcon
        self.showItemsInBar = showItemsInBar
        self.animateBar = animateBar
        self.barAnimationDuration = barAnimationDuration
        self.barStyle = barStyle
    }

    /// A blob stored before a key existed must keep the user's other settings, not throw
    /// them away — so every key added after 0.1.0 decodes as optional with its default.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Clamped to what the slider can ask for, the way the animation duration below is:
        // a longer delay stored by an older build leaves the bar open past what any setting
        // can now express.
        autoRehide = switch try container.decode(AutoRehide.self, forKey: .autoRehide) {
        case .afterDelay(let seconds): .afterDelay(seconds: min(max(seconds, 1), 10))
        case let other: other
        }
        enableAlwaysHiddenSection = try container.decode(Bool.self, forKey: .enableAlwaysHiddenSection)
        revealOnHover = try container.decode(Bool.self, forKey: .revealOnHover)
        showBouncerIcon = try container.decode(Bool.self, forKey: .showBouncerIcon)
        showItemsInBar = try container.decodeIfPresent(Bool.self, forKey: .showItemsInBar) ?? false
        animateBar = try container.decodeIfPresent(Bool.self, forKey: .animateBar) ?? true
        // Clamped to what the slider can ask for: a stored value from anywhere else drives an
        // animation the bar cannot be used during.
        barAnimationDuration = min(
            max(try container.decodeIfPresent(TimeInterval.self, forKey: .barAnimationDuration) ?? 0.18, 0.06),
            0.5
        )
        barStyle = try container.decodeIfPresent(BarStyle.self, forKey: .barStyle) ?? .automatic
    }
}
