import Foundation

/// What should collapse the menu bar again after it has been revealed.
public enum AutoRehide: Codable, Hashable, Sendable {
    case never
    case afterDelay(seconds: TimeInterval)
    case onFocusedAppChange
}

/// How long the pointer rests where hover reveals before it does, the way the Dock waits before
/// it shows.
public enum HoverDelay: Codable, Hashable, Sendable {
    /// The Dock's own auto-hide delay, read on every reveal so a change to it carries over.
    case matchDock
    case seconds(TimeInterval)

    /// The longest the custom delay can be set to.
    public static let longest: TimeInterval = 2
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
    /// Black, grown out of the display's notch, or out of a notch-sized point at the top centre
    /// of a display without one.
    case notch
    /// A flat colour of the user's choosing, in sRGB.
    case custom(red: Double, green: Double, blue: Double)

    /// The greys `automatic` resolves to, as white levels rather than colours so Settings
    /// stays free of AppKit. Shared so the bar and the settings swatch cannot drift apart.
    public static let automaticLight = 0.88
    public static let automaticDark = 0.24
}

/// The notch panel's two pages: the hidden items, and the todo list.
public enum NotchPage: Codable, Hashable, Sendable {
    case items
    case todos
}

/// The complete user-facing configuration. One value type so it round-trips as a
/// single encode/decode and comparing two states is a plain `==`.
public struct Preferences: Codable, Hashable, Sendable {
    public var autoRehide: AutoRehide
    public var enableAlwaysHiddenSection: Bool
    /// Reveal by moving the pointer into the menu bar, without a click.
    public var revealOnHover: Bool
    /// The same, but only near the notch, or the top centre of a display without one.
    public var revealNearNotch: Bool
    public var hoverDelay: HoverDelay
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
    /// A bookmark to the Markdown file the todo page reads and writes; `nil` while the page is off.
    /// A bookmark rather than a path, so the file is found again after it is moved or renamed.
    public var todoFile: Data?
    /// The page the notch panel was last left on, which is the one hover opens next.
    public var notchPage: NotchPage
    /// The colour each todo tag's chip is drawn in, by name; a tag left out is grey.
    public var tagColors: [String: String]

    public init(
        autoRehide: AutoRehide = .afterDelay(seconds: 10),
        enableAlwaysHiddenSection: Bool = false,
        revealOnHover: Bool = false,
        revealNearNotch: Bool = false,
        hoverDelay: HoverDelay = .matchDock,
        showBouncerIcon: Bool = true,
        showItemsInBar: Bool = false,
        animateBar: Bool = true,
        barAnimationDuration: TimeInterval = 0.18,
        barStyle: BarStyle = .automatic,
        todoFile: Data? = nil,
        notchPage: NotchPage = .items,
        tagColors: [String: String] = [:]
    ) {
        self.autoRehide = autoRehide
        self.enableAlwaysHiddenSection = enableAlwaysHiddenSection
        self.revealOnHover = revealOnHover
        self.revealNearNotch = revealNearNotch
        self.hoverDelay = hoverDelay
        self.showBouncerIcon = showBouncerIcon
        self.showItemsInBar = showItemsInBar
        self.animateBar = animateBar
        self.barAnimationDuration = barAnimationDuration
        self.barStyle = barStyle
        self.todoFile = todoFile
        self.notchPage = notchPage
        self.tagColors = tagColors
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
        revealNearNotch = try container.decodeIfPresent(Bool.self, forKey: .revealNearNotch) ?? false
        hoverDelay = switch try container.decodeIfPresent(HoverDelay.self, forKey: .hoverDelay) ?? .matchDock {
        case .seconds(let seconds): .seconds(min(max(seconds, 0), HoverDelay.longest))
        case .matchDock: .matchDock
        }
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
        todoFile = try container.decodeIfPresent(Data.self, forKey: .todoFile)
        notchPage = try container.decodeIfPresent(NotchPage.self, forKey: .notchPage) ?? .items
        tagColors = try container.decodeIfPresent([String: String].self, forKey: .tagColors) ?? [:]
    }
}
