import AppKit

/// A status item used as a section divider.
///
/// This is the whole hiding mechanism: macOS lays status items out right to left, so
/// growing one item's width pushes everything to its left past the edge of the screen.
/// No private API, no screen capture, no per-item bookkeeping — one width assignment.
@MainActor
final class ControlItem: NSObject {
    /// Wider than any conceivable menu bar, so everything left of the divider is
    /// pushed off screen regardless of display size.
    private static let expandedLength: CGFloat = 10_000
    /// Invisible in normal use, but non-zero so macOS keeps the item — and its saved
    /// position among the user's other items — alive.
    private static let hairlineLength: CGFloat = 1
    private static let editingLength: CGFloat = 24

    private let item: NSStatusItem
    private let symbolName: String
    /// Drawn on the divider's own button while its section is revealed, where the item is
    /// only a glyph wide. It has to be this item and not a neighbour: a preferred position
    /// is a hint, and macOS orders our items against other apps' however it likes, so any
    /// separate item can drift a slot off the boundary. The divider *is* the boundary, so
    /// the glyph on it is the one thing guaranteed to sit where hiding ends.
    private let markerImage: NSImage?

    /// Invoked when the marker is clicked.
    var onClick: (@MainActor () -> Void)?

    /// `true` collapses the section to this divider's left.
    var isExpanded = true {
        didSet { if isExpanded != oldValue { updateAppearance() } }
    }

    /// Widens the divider and gives it a glyph so the user can Cmd-drag items across it.
    var isEditing = false {
        didSet { if isEditing != oldValue { updateAppearance() } }
    }

    /// Frame in window-server coordinates, or `nil` before the item has a window.
    var frame: CGRect? { item.button?.window?.frame }

    /// - Parameter markerImage: shown while the section is revealed, so the boundary is
    ///   drawn exactly where hiding starts. Supplied by the app layer so branding stays
    ///   out of this module; should be a template image. `nil` leaves the divider
    ///   invisible in every state.
    init(autosaveName: String, symbolName: String, position: Double, markerImage: NSImage? = nil) {
        self.symbolName = symbolName
        self.markerImage = markerImage
        // Must precede creation: the slot is read when the item is made.
        StatusItemPosition.seed(position, for: autosaveName)
        item = NSStatusBar.system.statusItem(withLength: Self.expandedLength)
        item.autosaveName = autosaveName
        item.button?.setAccessibilityLabel("Bouncer section boundary")

        super.init()
        item.button?.target = self
        item.button?.action = #selector(clicked)
        updateAppearance()
    }

    /// Takes the divider out of the menu bar. The instance is dead afterwards.
    func remove() {
        NSStatusBar.system.removeStatusItem(item)
    }

    @objc private func clicked() {
        onClick?()
    }

    /// An expanded divider spans the whole bar, so it would otherwise intercept clicks on
    /// the app menu behind it. In every other state it is a glyph the user is meant to hit.
    private func applyClickThrough() {
        let ignores = isExpanded && !isEditing
        guard let window = item.button?.window else {
            DispatchQueue.main.async { [self] in
                item.button?.window?.ignoresMouseEvents = ignores
            }
            return
        }
        window.ignoresMouseEvents = ignores
    }

    private func updateAppearance() {
        applyClickThrough()

        if isExpanded {
            // Nothing to mark: everything this divider governs is off screen, and the
            // item is thousands of points wide, so a glyph would land off screen too.
            item.length = Self.expandedLength
            item.button?.image = nil
        } else if isEditing {
            item.length = Self.editingLength
            item.button?.image = NSImage(
                systemSymbolName: symbolName,
                accessibilityDescription: "Bouncer divider"
            )
        } else if let markerImage {
            item.length = NSStatusItem.variableLength
            item.button?.image = markerImage
        } else {
            item.length = Self.hairlineLength
            item.button?.image = nil
        }
    }
}
