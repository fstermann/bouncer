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

/// The notch panel's pages: the hidden items, the todo list, and the meeting notes.
public enum NotchPage: Codable, Hashable, Sendable {
    case items
    case todos
    case notes
}

/// The complete user-facing configuration. One value type so it round-trips as a
/// single encode/decode and comparing two states is a plain `==`.
public struct Preferences: Codable, Hashable, Sendable {
    /// Hide menu bar items behind Bouncer's dividers. Off, Bouncer puts no divider in the bar.
    public var enableMenuBarItems: Bool
    /// The todo panel under the notch. At least one of the modes is always on.
    public var enableTodos: Bool
    /// The meeting notes panel under the notch.
    public var enableNotes: Bool
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
    /// Grow the notch panels out of the notch and back into it, rather than having them appear
    /// at once.
    public var animateBar: Bool
    /// How long that growth takes, in seconds.
    public var barAnimationDuration: TimeInterval
    /// A bookmark to the Markdown file the todo page reads and writes; `nil` for a local file in
    /// Application Support.
    /// A bookmark rather than a path, so the file is found again after it is moved or renamed.
    public var todoFile: Data?
    /// A bookmark to the folder meeting notes are kept in, one Markdown file each; `nil` for a local
    /// folder in Application Support.
    public var notesFolder: Data?
    /// The page the notch panel was last left on, which is the one hover opens next.
    public var notchPage: NotchPage
    /// The colour each todo tag's chip is drawn in, by name; a tag left out is grey.
    public var tagColors: [String: String]
    /// The order todo tags' chips were dragged into; a tag left out follows those in it.
    public var tagOrder: [String]

    public init(
        enableMenuBarItems: Bool = true,
        enableTodos: Bool = true,
        enableNotes: Bool = false,
        autoRehide: AutoRehide = .afterDelay(seconds: 10),
        enableAlwaysHiddenSection: Bool = false,
        revealOnHover: Bool = false,
        revealNearNotch: Bool = false,
        hoverDelay: HoverDelay = .matchDock,
        showBouncerIcon: Bool = true,
        showItemsInBar: Bool = false,
        animateBar: Bool = true,
        barAnimationDuration: TimeInterval = 0.18,
        todoFile: Data? = nil,
        notesFolder: Data? = nil,
        notchPage: NotchPage = .items,
        tagColors: [String: String] = [:],
        tagOrder: [String] = []
    ) {
        self.enableMenuBarItems = enableMenuBarItems
        self.enableTodos = enableTodos
        self.enableNotes = enableNotes
        self.autoRehide = autoRehide
        self.enableAlwaysHiddenSection = enableAlwaysHiddenSection
        self.revealOnHover = revealOnHover
        self.revealNearNotch = revealNearNotch
        self.hoverDelay = hoverDelay
        self.showBouncerIcon = showBouncerIcon
        self.showItemsInBar = showItemsInBar
        self.animateBar = animateBar
        self.barAnimationDuration = barAnimationDuration
        self.todoFile = todoFile
        self.notesFolder = notesFolder
        self.notchPage = notchPage
        self.tagColors = tagColors
        self.tagOrder = tagOrder
    }

    /// A blob stored before a key existed must keep the user's other settings, not throw
    /// them away — so every key added after 0.1.0 decodes as optional with its default.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Both, as every build before the choice offered.
        enableMenuBarItems = try container.decodeIfPresent(Bool.self, forKey: .enableMenuBarItems) ?? true
        enableTodos = try container.decodeIfPresent(Bool.self, forKey: .enableTodos) ?? true
        enableNotes = try container.decodeIfPresent(Bool.self, forKey: .enableNotes) ?? false
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
        todoFile = try container.decodeIfPresent(Data.self, forKey: .todoFile)
        notesFolder = try container.decodeIfPresent(Data.self, forKey: .notesFolder)
        notchPage = try container.decodeIfPresent(NotchPage.self, forKey: .notchPage) ?? .items
        tagColors = try container.decodeIfPresent([String: String].self, forKey: .tagColors) ?? [:]
        tagOrder = try container.decodeIfPresent([String].self, forKey: .tagOrder) ?? []
    }
}
