import Foundation

/// The slot a status item occupies in the menu bar.
///
/// macOS persists this per item under `NSStatusItem Preferred Position <autosaveName>`
/// in the owning app's defaults, and reorders when the user Cmd-drags. Larger values
/// sit further left. Without a seed every new item is created leftmost, which would put
/// Bouncer's own icon to the left of its dividers — where the dividers immediately push
/// it off screen.
///
/// A seed only sets the *initial* slot: once macOS has placed the item it rewrites the
/// value to the item's real offset from the right edge. And it is only a hint — macOS
/// orders our items against every other app's however it likes, so no value here can
/// guarantee what ends up next to what. Nothing depends on that: the only glyph that has
/// to be exactly on a boundary is drawn on the divider that *is* the boundary.
public enum StatusItemPosition {
    /// Public because it is what says where the hidden section ends: the section is the run of
    /// items packed against this divider's left edge, and `StandaloneBar` has to be able to pick
    /// it out of the bar by name. Nothing else identifies it — collapsed it is a hairline the
    /// size of a real item.
    public static let hiddenDividerName = "bouncer.divider.hidden"
    static let alwaysHiddenDividerName = "bouncer.divider.alwaysHidden"
    static let iconName = "bouncer.icon"

    /// Bouncer's items start as one cluster at the right end of the bar, ordered right to
    /// left: icon, hidden divider. Everything of the user's therefore starts out left of
    /// the divider — hidden when collapsed, which is what makes it a meaningful boundary.
    /// Drag items right of the divider to keep them visible.
    static let hiddenDivider = 3.0
    /// Far right, so the icon is always reachable regardless of divider state. It is a
    /// button, not a boundary: the user's always-visible items may well sort between it
    /// and the divider, and the divider's own glyph marks where hiding ends.
    static let icon = 1.0
    /// Left of everything, so the always-hidden section starts empty: it is off by
    /// default, and turning it on must not swallow the whole bar. macOS clamps a seed
    /// this large to the bar's extent, which puts the divider leftmost.
    static let alwaysHiddenDivider = 10_000.0

    /// Seeds the slot only when the item has never been placed. A user who has dragged
    /// Bouncer's items keeps their arrangement.
    static func seed(_ position: Double, for autosaveName: String) {
        let key = "NSStatusItem Preferred Position \(autosaveName)"
        guard UserDefaults.standard.object(forKey: key) == nil else { return }
        UserDefaults.standard.set(position, forKey: key)
    }
}
