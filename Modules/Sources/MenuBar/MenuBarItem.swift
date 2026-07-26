import CoreGraphics
import Foundation

/// A status item belonging to some app, as seen from the window server.
public struct MenuBarItem: Identifiable, Hashable, Sendable {
    public let windowID: CGWindowID
    public let ownerPID: pid_t
    public let ownerName: String
    public let title: String?
    public let frame: CGRect
    /// `false` once a divider has pushed the item past the edge of the display.
    public let isOnScreen: Bool

    public var id: CGWindowID { windowID }
}

/// Reads the current menu bar layout from the window server.
///
/// There is no public API for enumerating other apps' status items, so we read the
/// window list and keep only windows on the status-item layer. Frames and owners come
/// back without any permission prompt; only capturing item *images* would need Screen
/// Recording, which this deliberately avoids.
public enum MenuBarItemScanner {
    /// `NSStatusWindowLevel` — the CoreGraphics window layer status items live on.
    private static let statusItemLayer = 25

    /// Ordered left to right. Cheap enough to call on demand; do not poll it.
    public static func scan() -> [MenuBarItem] {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return raw
            .compactMap(item(from:))
            .sorted { $0.frame.minX < $1.frame.minX }
    }

    private static func item(from info: [String: Any]) -> MenuBarItem? {
        guard let layer = info[kCGWindowLayer as String] as? Int, layer == statusItemLayer,
              let windowID = info[kCGWindowNumber as String] as? CGWindowID,
              let pid = info[kCGWindowOwnerPID as String] as? pid_t,
              let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
              let frame = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
        else { return nil }

        return MenuBarItem(
            windowID: windowID,
            ownerPID: pid,
            ownerName: info[kCGWindowOwnerName as String] as? String ?? "",
            title: info[kCGWindowName as String] as? String,
            frame: frame,
            isOnScreen: info[kCGWindowIsOnscreen as String] as? Bool ?? false
        )
    }
}
