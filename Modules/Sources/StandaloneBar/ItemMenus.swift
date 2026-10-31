import AppKit

/// Whether a status item's menu or panel is showing, read once from the window list when asked.
///
/// Told apart by level rather than position: a menu's frame includes its shadow, so its top edge is
/// not where it meets the bar. Menus sit at the pop-up level; Control Center's panels sit just
/// under the items. Either one reaches down from the bar.
enum ItemMenus {
    @MainActor
    static var isShowing: Bool {
        guard let barHeight = NSScreen.main?.menuBarHeight else { return false }
        let own = ProcessInfo.processInfo.processIdentifier
        let popUp = Int(CGWindowLevelForKey(.popUpMenuWindow))
        let status = Int(CGWindowLevelForKey(.statusWindow))
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return windows.contains { window in
            guard window[kCGWindowOwnerPID as String] as? Int32 != own,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  layer == popUp || (status - 3..<status - 1).contains(layer),
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else { return false }
            return frame.minY <= barHeight && frame.maxY > barHeight
        }
    }
}
