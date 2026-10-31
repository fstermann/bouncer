import AppKit

extension StandaloneBarController {
    /// Switches the notch panel to the todo page. `nil` hides the switch, which sits at the right
    /// end of the menu bar row, over the section's last item.
    public var onSwitchPage: (@MainActor () -> Void)? {
        get { shield.onSwitchPage }
        set {
            shield.onSwitchPage = newValue
            tab.onSwitch = newValue
            cover.pageSwitch.isHidden = newValue == nil
        }
    }

    /// Opens the panel under another that takes its shape first, the way the todo page turns into
    /// this one.
    ///
    /// The windows go up invisible, and `shape` is handed their outline before anything is revealed;
    /// once it returns they show, under whatever now has their shape, and only then is the section
    /// revealed beneath them. Shown any sooner, they stick out past the panel still changing shape,
    /// and the section, revealed with them hidden, shows its real items in the menu bar.
    public func open(closingWhenLeft: Bool, takingShape shape: @escaping @MainActor (CGRect) async -> Void) async {
        if #available(macOS 27, *) {
            // Returns once the band covers the section, so the page fades off it as the bar opens.
            let takeOver = TakeOver(shape: shape)
            self.takeOver = takeOver
            return await withCheckedContinuation { covered in
                takeOver.covered = covered
                Task {
                    await open(closingWhenLeft: closingWhenLeft, animated: false)
                    takeOver.letGo()
                }
            }
        }
        isPanelConcealed = true
        cover.arrival = { [weak self] in
            guard let self, let outline else { return }
            await shape(outline)
            isPanelConcealed = false
        }
        await open(closingWhenLeft: closingWhenLeft, animated: false)
        cover.arrival = nil
        isPanelConcealed = false
    }

    /// The panel's outline, cover and shelf together, in AppKit screen coordinates: what the todo
    /// page grows out of when switched to.
    public var panelFrame: CGRect? { isOpen ? (isInTheBar ? tab.outline : outline) : nil }

    private var isPanelConcealed: Bool {
        get { cover.isConcealed }
        set {
            cover.isConcealed = newValue
            bar.isConcealed = newValue
            shield.isConcealed = newValue
        }
    }

    /// Read off the shelf alone, reaching up to the top of the display: the cover is as wide, and
    /// just after an open it is still gliding onto the section, so its own frame is not where it
    /// will rest. The shelf is placed where it rests at once.
    private var outline: CGRect? {
        guard let shelf = bar.panel, let window = shelf.window, let screen = window.screen else { return nil }
        let shelfFrame = window.convertToScreen(shelf.convert(shelf.bounds, to: nil))
        return CGRect(
            x: shelfFrame.minX, y: shelfFrame.minY,
            width: shelfFrame.width, height: screen.frame.maxY - shelfFrame.minY
        )
    }
}

/// A todo page turning into the bar on macOS 27: it takes the band's shape, and is let go once the
/// band covers the section underneath it.
@MainActor
final class TakeOver {
    let shape: @MainActor (CGRect) async -> Void
    var covered: CheckedContinuation<Void, Never>?

    init(shape: @escaping @MainActor (CGRect) async -> Void) {
        self.shape = shape
    }

    func letGo() {
        covered?.resume()
        covered = nil
    }
}

/// The switch to the todo page: dimmed white on a dark disc, so it reads on black, on grey and on
/// glass alike without knowing which the cover is painted with, and sits back like the todo page's.
@MainActor
enum PageSwitchGlyph {
    static let size: CGFloat = 20
    /// How far in from the section's right end it sits.
    static let inset: CGFloat = 2

    static func make() -> NSImageView {
        let glyph = NSImageView()
        glyph.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Show todos")
        glyph.symbolConfiguration = .init(pointSize: 11, weight: .regular)
        glyph.contentTintColor = .white.withAlphaComponent(0.6)
        glyph.wantsLayer = true
        glyph.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        glyph.layer?.cornerRadius = size / 2
        glyph.autoresizingMask = [.minXMargin, .minYMargin, .maxYMargin]
        glyph.isHidden = true
        return glyph
    }
}
