import AppKit

/// The one colour the standalone bar is made of.
///
/// The cover over the real section and the shelf below it are painted with it, so the two
/// read as a single panel hanging off the menu bar rather than as a patch stuck over the bar
/// and a separate strip underneath.
///
/// Solid, and not a picture of the bar. A capture matches the bar exactly at the moment it is
/// taken and then goes stale — the wallpaper scrolls, a menu opens and casts a shadow the
/// still knows nothing about — and one spanning the bar's whole width was visible as a twitch
/// each time it went up and came down. A colour that is honestly its own thing beats a
/// photograph that is almost right.
enum BarSurface {
    /// Fully opaque. The cover's whole job is to hide the icons underneath it, and anything
    /// short of opaque leaves them ghosting through.
    static let colour = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0.24, alpha: 1)
            : NSColor(white: 0.88, alpha: 1)
    }
}
