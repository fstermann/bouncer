import AppKit
import MenuBar
import Settings

extension StandaloneBarController {
    /// Switches the notch panel to another page, picked from the page button.
    public var onSwitchPage: (@MainActor (NotchPage) -> Void)? {
        get { cover.pageButton.onPick }
        set {
            cover.pageButton.onPick = newValue
            tab.pageButton.onPick = newValue
        }
    }

    /// The pages that are on, offered right of the notch, or over the section's right end on a
    /// display without one.
    public var pages: [NotchPage] {
        get { cover.pageButton.pages }
        set {
            for button in [cover.pageButton, tab.pageButton, tab.coverButton] {
                button.pages = newValue
                button.current = .items
            }
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
        closing.waitsForPointer = true
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

/// Opens a page growing out of the bar, handed `covered` to call once it covers the bar.
public typealias PageOpening = @MainActor (_ covered: @MainActor () async -> Void) async -> Void

/// A todo or notes page turning into the bar on macOS 27: it takes the band's shape, and is let go once the
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
