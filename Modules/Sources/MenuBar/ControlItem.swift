import AppKit

/// A status item used as a section divider.
///
/// This is the whole hiding mechanism: macOS lays status items out right to left, so
/// growing one item's width pushes everything to its left past the edge of the screen.
/// No private API, no screen capture, no per-item bookkeeping — one width assignment.
@MainActor
final class ControlItem: NSObject {
    /// Invisible in normal use, but non-zero so macOS keeps the item — and its saved
    /// position among the user's other items — alive.
    private static let hairlineLength: CGFloat = 1

    private let item: NSStatusItem
    /// Drawn on the divider's own button while its section is revealed, where the item is
    /// only a glyph wide. It has to be this item and not a neighbour: a preferred position
    /// is a hint, and macOS orders our items against other apps' however it likes, so any
    /// separate item can drift a slot off the boundary. The divider *is* the boundary, so
    /// the glyph on it is the one thing guaranteed to sit where hiding ends.
    private let markerImage: NSImage?

    /// Where the right edge last sat while the divider was narrow. An expanded divider's frame keeps
    /// its old origin, so this is the one reading of its slot that can be trusted.
    private(set) var restingRightEdge: CGFloat?
    /// Whether `restingRightEdge` has stopped moving since the divider was created.
    private var hasSettled = false
    private var settling: DispatchWorkItem?
    /// Whether the divider is wide right now, hiding its section. Its frame is stale while it is.
    private var isWide = false
    private var moveObserver: NSObjectProtocol?

    /// The frame of an item this divider must never hide: Bouncer's own icon.
    var keepsVisible: (@MainActor () -> CGRect?)?

    /// Invoked when the marker is clicked.
    var onClick: (@MainActor () -> Void)?

    /// `true` collapses the section to this divider's left.
    var isExpanded = true {
        didSet { if isExpanded != oldValue { updateAppearance() } }
    }

    /// Whether the boundary is drawn while its section is revealed.
    ///
    /// The marker says where hiding ends, which is worth knowing when the items are sitting
    /// in the bar — and worth nothing when they are being shown somewhere else entirely.
    var showsMarker = true {
        didSet { if showsMarker != oldValue { updateAppearance() } }
    }

    /// Extra width taken while the section is revealed without a marker, pushing it that much
    /// further left. Ignored while expanded, where the divider is already wider than any bar.
    var padding: CGFloat = 0 {
        didSet { if padding != oldValue { updateAppearance() } }
    }

    /// Frame in window-server coordinates, or `nil` before the item has a window.
    var frame: CGRect? { item.button?.window?.frame }

    /// - Parameter markerImage: shown while the section is revealed, so the boundary is
    ///   drawn exactly where hiding starts. Supplied by the app layer so branding stays
    ///   out of this module; should be a template image. `nil` leaves the divider
    ///   invisible in every state.
    init(autosaveName: String, position: Double, markerImage: NSImage? = nil) {
        self.markerImage = markerImage
        // Must precede creation: the slot is read when the item is made.
        StatusItemPosition.seed(position, for: autosaveName)
        item = NSStatusBar.system.statusItem(withLength: Self.hairlineLength)
        item.autosaveName = autosaveName
        item.button?.setAccessibilityLabel("Bouncer section boundary")

        super.init()
        item.button?.target = self
        item.button?.action = #selector(clicked)
        if Self.notch(for: item.button?.window) != nil {
            moveObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification, object: item.button?.window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.windowMoved() }
            }
        }
        updateAppearance()
    }

    /// Takes the divider out of the menu bar. The instance is dead afterwards.
    func remove() {
        moveObserver.map(NotificationCenter.default.removeObserver)
        moveObserver = nil
        settling?.cancel()
        NSStatusBar.system.removeStatusItem(item)
    }

    /// A new item gets its place in the bar only after it was asked to expand, and the items
    /// created with it land around then too, shifting it. So expanding waits until it has stopped
    /// moving: expanded too early, it fills room an item landing to its right needed, and macOS 27
    /// overflows that item rather than the divider.
    private func windowMoved() {
        guard let window = item.button?.window, let screen = window.screen,
              screen.frame.intersects(window.frame), !isWide
        else { return }
        restingRightEdge = window.frame.maxX
        lookAgain()
    }

    /// Decides again whether to hide, once the bar has been still for a moment: on a move of the
    /// divider's own, or of the icon it must not hide. Waiting is what keeps it from expanding
    /// under an item still being dragged, which would then land in a full bar and be overflowed.
    func lookAgain() {
        settling?.cancel()
        let settle = DispatchWorkItem { [weak self] in
            guard let self else { return }
            hasSettled = true
            if isExpanded { updateAppearance() }
        }
        settling = settle
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay, execute: settle)
    }

    private static let settleDelay: TimeInterval = 0.3

    private var expandedLength: CGFloat? {
        ExpandedDivider.length(
            rightEdge: hasSettled ? restingRightEdge : nil,
            notch: Self.notch(for: item.button?.window),
            keeping: keepsVisible?()?.maxX
        )
    }

    /// The notch an expanded divider has to reach into, `nil` where the bar still lets it run off the display.
    private static func notch(for window: NSWindow?) -> ClosedRange<CGFloat>? {
        guard #available(macOS 27, *), let screen = window?.screen ?? NSScreen.main else { return nil }
        let notch = DisplayNotch.range(
            left: screen.auxiliaryTopLeftArea, right: screen.auxiliaryTopRightArea, screen: screen.frame
        )
        return notch.isReal ? notch.range : nil
    }

    @objc private func clicked() {
        onClick?()
    }

    /// An expanded divider spans the whole bar, so it would otherwise intercept clicks on
    /// the app menu behind it. In every other state it is a glyph the user is meant to hit.
    private func applyClickThrough() {
        guard let window = item.button?.window else {
            DispatchQueue.main.async { [self] in
                item.button?.window?.ignoresMouseEvents = isExpanded
            }
            return
        }
        window.ignoresMouseEvents = isExpanded
    }

    private func updateAppearance() {
        applyClickThrough()

        if isExpanded {
            // Nothing to mark: everything this divider governs is hidden, and a glyph would
            // land under the notch or off screen with it.
            let length = expandedLength
            isWide = length != nil
            if let length {
                item.length = length
                item.button?.image = nil
            } else if hasSettled, let markerImage {
                // Held back for the icon, so the section is in plain view: mark where it ends,
                // which is where the icon has to be dragged past.
                item.length = NSStatusItem.variableLength
                item.button?.image = markerImage
            } else {
                item.length = Self.hairlineLength
                item.button?.image = nil
            }
        } else if let markerImage, showsMarker {
            isWide = false
            item.length = NSStatusItem.variableLength
            item.button?.image = markerImage
        } else {
            isWide = false
            item.length = Self.hairlineLength + padding
            item.button?.image = nil
        }
    }
}
