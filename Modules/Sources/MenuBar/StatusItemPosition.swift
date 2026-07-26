import Foundation

/// The slot a status item occupies in the menu bar.
///
/// macOS persists this per item under `NSStatusItem Preferred Position <autosaveName>`
/// in the owning app's defaults, and reorders when the user Cmd-drags. Larger values
/// sit further left. Without a seed every new item is created leftmost, which would put
/// Bouncer's own icon to the left of its dividers — where the dividers immediately push
/// it off screen.
enum StatusItemPosition {
    /// Far left, so nothing of the user's is hidden until they arrange it that way.
    static let alwaysHiddenDivider = 1001.0
    static let hiddenDivider = 1000.0
    /// Far right, so the icon is always reachable regardless of divider state.
    static let icon = 1.0

    /// Seeds the slot only when the item has never been placed. A user who has dragged
    /// Bouncer's items keeps their arrangement.
    static func seed(_ position: Double, for autosaveName: String) {
        let key = "NSStatusItem Preferred Position \(autosaveName)"
        guard UserDefaults.standard.object(forKey: key) == nil else { return }
        UserDefaults.standard.set(position, forKey: key)
    }
}
