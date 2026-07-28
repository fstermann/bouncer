import AppKit

/// Reads the menu bar's status items out of the window server.
///
/// Geometry is the one thing about other apps' items that costs no permission: frames are
/// exact, and they are reported whether the item is on screen or parked past the edge of
/// the display. Identity is not — every status item is hosted by Control Center, so they
/// all report the same owner and an empty window name until Screen Recording is granted.
/// Nothing here may depend on knowing which app an item belongs to.
public enum StatusItemScanner {
    /// Status items live on this window layer. Everything else in the menu bar band — the
    /// bar itself, menus, other apps' overlays — is on a different one.
    static let statusWindowLayer = 25

    /// The menu bar band. Items are exactly as tall as the bar; a taller window at y = 0 is
    /// something else that happens to start at the top of the screen.
    static let maximumItemHeight: CGFloat = 40

    /// Parses window-server dictionaries into items.
    ///
    /// Split from the call that fetches them so the filtering can be tested against
    /// recorded window lists, with no window server and no running app.
    public static func items(from windows: [[String: Any]]) -> [MenuBarItem] {
        windows.compactMap { window in
            guard window[kCGWindowLayer as String] as? Int == statusWindowLayer,
                  let number = window[kCGWindowNumber as String] as? Int,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  frame.minY == 0,
                  frame.height <= maximumItemHeight
            else { return nil }
            return MenuBarItem(windowID: UInt32(number), frame: frame)
        }
        .sorted { $0.frame.minX < $1.frame.minX }
    }

    /// Every status item currently in the bar, ordered left to right, dividers included.
    ///
    /// `.optionAll` rather than `.optionOnScreenOnly` on purpose: a hidden section is
    /// off screen, and it is exactly the section the standalone bar exists to show.
    public static func scan() -> [MenuBarItem] {
        let options = CGWindowListOption(arrayLiteral: .optionAll, .excludeDesktopElements)
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        return items(from: windows)
    }
}
