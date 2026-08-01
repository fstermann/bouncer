import AppKit
import Settings

/// What the standalone bar is made of: the user's chosen style, resolved into paint.
///
/// The cover over the real section and the shelf below it are dressed alike, so the two
/// read as a single panel hanging off the menu bar rather than as a patch stuck over the bar
/// and a separate strip underneath.
///
/// A colour or a glass, and not a picture of the bar. A capture matches the bar exactly at the
/// moment it is taken and then goes stale — the wallpaper scrolls, a menu opens and casts a
/// shadow the still knows nothing about — and one spanning the bar's whole width was visible as
/// a twitch each time it went up and came down. A surface that is honestly its own thing beats
/// a photograph that is almost right.
enum BarSurface {
    /// Fully opaque. The cover's whole job is to hide the icons underneath it, and anything
    /// short of opaque leaves them ghosting through.
    static let colour = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: BarStyle.automaticDark, alpha: 1)
            : NSColor(white: BarStyle.automaticLight, alpha: 1)
    }

    /// Paints `view` in the user's chosen style, and returns the veil laid over glass —
    /// `nil` for the solid styles, which have nothing to veil. Called on both halves of the
    /// panel, with the same style, so they keep reading as one piece.
    ///
    /// Glass refracts whatever is behind it, and behind the cover that is the very icons it
    /// exists to hide — glass backed by an opaque colour refracts nothing and reads as plain
    /// paint, which is worse. So the glass is dimmed by a fade instead, heaviest where the
    /// panel hangs off the menu bar and lightest at its foot: a knowing trade of airtight
    /// hiding for a panel that reads as one piece growing out of the bar. The two fades meet
    /// at the same alpha, so the seam between the windows does not show as a step.
    @MainActor
    static func dress(_ view: NSView, in style: BarStyle, coveringIcons: Bool) -> NSView? {
        view.layer?.backgroundColor = colour(for: style).cgColor
        guard #available(macOS 26.0, *) else { return nil }
        // The cover's surface is dressed once per open, and the dressing must not stack:
        // a second open would otherwise lay a second fade over the first.
        view.subviews
            .filter { $0 is NSGlassEffectView || $0 is GradientView || $0 is VeilView }
            .forEach { $0.removeFromSuperview() }
        guard style == .glass else { return nil }
        view.layer?.backgroundColor = nil

        // Liquid Glass draws a bright rim along its edges, and the panel is two sheets
        // meeting at the menu bar's lower edge — a rim on each side of that line reads as a
        // cut through the panel. Each sheet runs past the seam instead and the clip swallows
        // the rim there, leaving rims only on the panel's outside edges.
        var sheet = view.bounds
        sheet.size.height += Self.seamOverhang
        if coveringIcons { sheet.origin.y -= Self.seamOverhang }
        let glass = NSGlassEffectView(frame: sheet)
        glass.autoresizingMask = [.width, .height]
        // The glass would round every corner itself; the shape is the clip's to decide —
        // square against the bar, rounded only at the shelf's feet.
        glass.cornerRadius = 0
        view.addSubview(glass, positioned: .below, relativeTo: nil)

        let fade = GradientView(frame: view.bounds)
        fade.wantsLayer = true
        fade.autoresizingMask = [.width, .height]
        let alphas = coveringIcons ? Self.coverFade : Self.shelfFade
        (fade.layer as? CAGradientLayer)?.colors = [
            colour.withAlphaComponent(alphas.bottom).cgColor,
            colour.withAlphaComponent(alphas.top).cgColor
        ]
        view.addSubview(fade, positioned: .above, relativeTo: glass)

        let veil = VeilView(frame: view.bounds)
        veil.autoresizingMask = [.width, .height]
        veil.wantsLayer = true
        veil.layer?.backgroundColor = colour.cgColor
        veil.alphaValue = Self.veilDim
        view.addSubview(veil, positioned: .above, relativeTo: fade)
        return veil
    }

    /// Fades the veils towards dimmed or clear, and returns once they have finished.
    ///
    /// One animation group for however many veils are passed, the way `Slide` runs the two
    /// halves as one panel: groups started separately can start a frame apart, and a frame
    /// apart is a step at the seam the veil is meant to keep smooth.
    ///
    /// The veil mutes the pop of the section landing under the cover or leaving it — the
    /// window server moves it in one frame — and it is translucent, deliberately: an opaque
    /// veil hid the pop completely, but was itself a solid block popping in and out of a
    /// panel that is otherwise glass.
    @MainActor
    static func fade(_ veils: [NSView?], toDimmed dimmed: Bool, over duration: TimeInterval?) async {
        let views = veils.compactMap(\.self)
        guard !views.isEmpty else { return }
        let alpha: CGFloat = dimmed ? veilDim : 0
        guard let duration else {
            for view in views { view.alphaValue = alpha }
            return
        }
        await withCheckedContinuation { continuation in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                for view in views { view.animator().alphaValue = alpha }
            } completionHandler: {
                continuation.resume()
            }
        }
    }

    /// The cover's end never drops below what still has icons to hide; the shelf's picks up
    /// where the cover left off and fades towards the desktop.
    private static let coverFade = (top: 0.85, bottom: 0.6)
    private static let shelfFade = (top: 0.6, bottom: 0.3)
    /// How dark the veil gets. Lighter leaks more of the pop; darker drifts back towards a
    /// solid block.
    private static let veilDim: CGFloat = 0.4
    /// Comfortably wider than the rim the glass draws.
    private static let seamOverhang: CGFloat = 12

    private static func colour(for style: BarStyle) -> NSColor {
        switch style {
        case .automatic, .glass:
            colour
        case .custom(let red, let green, let blue):
            // Opaque no matter what was stored: the cover hides icons, and any alpha shows them.
            NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
        }
    }
}

/// Its layer *is* the gradient, so it follows the view through resizes on its own.
private final class GradientView: NSView {
    override func makeBackingLayer() -> CALayer { CAGradientLayer() }
}

/// A type of its own only so a re-dress can tell the veil from views it does not own.
private final class VeilView: NSView {}
