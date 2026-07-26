import Foundation

/// The three regions the menu bar is divided into, ordered right to left as macOS
/// lays status items out.
public enum MenuBarSection: String, CaseIterable, Codable, Sendable {
    /// Always on screen.
    case visible
    /// Collapsed by default, revealed on demand.
    case hidden
    /// Collapsed even when `hidden` is revealed.
    case alwaysHidden

    public var displayName: String {
        switch self {
        case .visible: "Visible"
        case .hidden: "Hidden"
        case .alwaysHidden: "Always Hidden"
        }
    }
}

/// How much of the menu bar is currently on screen.
public enum MenuBarVisibility: Hashable, Sendable, CaseIterable {
    case collapsed
    case revealed
    case fullyRevealed

    public func shows(_ section: MenuBarSection) -> Bool {
        switch (self, section) {
        case (_, .visible): true
        case (.collapsed, _): false
        case (.revealed, .hidden): true
        case (.revealed, .alwaysHidden): false
        case (.fullyRevealed, _): true
        }
    }
}
