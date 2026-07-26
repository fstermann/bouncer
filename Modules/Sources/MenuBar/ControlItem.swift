import AppKit

/// A status item used as a section divider.
///
/// This is the whole hiding mechanism: macOS lays status items out right to left, so
/// growing one item's width pushes everything to its left past the edge of the screen.
/// No private API, no screen capture, no per-item bookkeeping — one width assignment.
@MainActor
final class ControlItem {
    /// Wider than any conceivable menu bar, so everything left of the divider is
    /// pushed off screen regardless of display size.
    private static let expandedLength: CGFloat = 10_000
    /// Invisible in normal use, but non-zero so macOS keeps the item — and its saved
    /// position among the user's other items — alive.
    private static let hairlineLength: CGFloat = 1
    private static let editingLength: CGFloat = 24

    private let item: NSStatusItem
    private let symbolName: String

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

    init(autosaveName: String, symbolName: String) {
        self.symbolName = symbolName
        item = NSStatusBar.system.statusItem(withLength: Self.expandedLength)
        item.autosaveName = autosaveName
        item.button?.setAccessibilityLabel("Bouncer divider")
        updateAppearance()
    }

    private func updateAppearance() {
        if isExpanded {
            item.length = Self.expandedLength
            item.button?.image = nil
        } else if isEditing {
            item.length = Self.editingLength
            item.button?.image = NSImage(
                systemSymbolName: symbolName,
                accessibilityDescription: "Bouncer divider"
            )
        } else {
            item.length = Self.hairlineLength
            item.button?.image = nil
        }
    }
}
