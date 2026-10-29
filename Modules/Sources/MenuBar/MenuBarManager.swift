import AppKit
import BouncerFoundation
import Observation
import Settings

/// Owns the menu bar's structure: the dividers that define the sections, Bouncer's own
/// status item, and which sections are currently on screen.
///
/// Deliberately knows nothing about *why* visibility changes — hover and auto-rehide
/// live in `RevealController`.
@MainActor
@Observable
public final class MenuBarManager {
    public private(set) var visibility: MenuBarVisibility = .collapsed

    /// Suspends automatic hiding while something else is showing the section.
    ///
    /// The standalone bar reveals the section in order to replicate it, and the items have to
    /// stay put for as long as that bar is open. Auto-rehide would otherwise collapse them a
    /// few seconds later — or the moment a replica's click activates the item's own app —
    /// leaving a bar of replicas whose menus open off screen.
    public var isRevealHeld = false

    /// Bouncer's own status item, when `showBouncerIcon` is enabled. Assign a `menu`
    /// to it from the app layer; left clicks toggle visibility.
    public private(set) var iconItem: NSStatusItem?

    /// Invoked on a left click of Bouncer's icon.
    public var onIconClick: (@MainActor () -> Void)?

    /// Shown on a right click of Bouncer's icon.
    public var iconMenu: NSMenu?

    private let settings: SettingsStore
    private let iconImage: NSImage?
    private let iconOpenImage: NSImage?
    /// Held rather than passed straight through, because the dividers are only built while
    /// their sections are switched on.
    private let dividerImage: NSImage?
    private let outerDividerImage: NSImage?
    /// Exists only while menu bar items are enabled, for the same reason as the always-hidden one.
    private var hiddenDivider: ControlItem?
    /// Exists only while the always-hidden section is enabled: a divider that is in the
    /// bar hides whatever is left of it, and a section the user cannot reveal must hide
    /// nothing. Not being there also costs no width.
    private var alwaysHiddenDivider: ControlItem?
    private var observation: ObservationLoop?
    private var iconMoves: NSObjectProtocol?

    /// - Parameters:
    ///   - iconImage: Bouncer's menu bar glyph, the button at the right end of the bar.
    ///   - iconOpenImage: the same mark with its dot hollowed out, drawn while anything
    ///     is revealed.
    ///   - dividerImage: the mark's bars and a boundary rule, drawn on the hidden divider
    ///     where the section ends on the right.
    ///   - outerDividerImage: the same mirrored, drawn on the always-hidden divider so the
    ///     two boundaries bracket the hidden section between them.
    ///
    /// All are supplied by the app layer so branding stays out of this module, and all
    /// should be template images.
    public init(
        settings: SettingsStore,
        iconImage: NSImage?,
        iconOpenImage: NSImage?,
        dividerImage: NSImage?,
        outerDividerImage: NSImage?
    ) {
        self.settings = settings
        self.iconImage = iconImage
        self.iconOpenImage = iconOpenImage
        self.dividerImage = dividerImage
        self.outerDividerImage = outerDividerImage
        observation = ObservationLoop { [weak self] in
            self?.applyPreferences(self?.settings.preferences ?? Preferences())
        }
        apply(visibility)
    }

    /// Hides the boundary markers while the section is being shown somewhere other than
    /// the menu bar, where a boundary is a glyph that marks nothing.
    public func setBoundaryMarkersVisible(_ areVisible: Bool) {
        hiddenDivider?.showsMarker = areVisible
        alwaysHiddenDivider?.showsMarker = areVisible
    }

    /// How far further left the revealed hidden section is pushed, by widening its divider. Only
    /// takes effect while the boundary markers are hidden, and goes back to zero on a collapse.
    public var sectionShift: CGFloat {
        get { hiddenDivider?.padding ?? 0 }
        set { hiddenDivider?.padding = newValue }
    }

    /// Where the hidden section ends on the right, in window-server x: everything it holds lands
    /// left of this when revealed. `nil` before the divider has been placed, and below macOS 27,
    /// where nothing reads it.
    public var hiddenSectionEnd: CGFloat? { hiddenDivider?.restingRightEdge }

    #if DEV
    public var devState: String {
        let icon = (iconItem?.button?.window?.frame).map { "\($0)" } ?? "nil"
        return "hidden divider \(hiddenDivider?.devState ?? "none")\n"
            + "always-hidden divider \(alwaysHiddenDivider?.devState ?? "none")\nicon \(icon)"
    }
    #endif

    public func setVisibility(_ newValue: MenuBarVisibility) {
        guard newValue != visibility else { return }
        visibility = newValue
        apply(newValue)
        Log.menuBar.debug("Visibility → \(String(describing: newValue), privacy: .public)")
    }

    /// Collapses if anything is revealed, otherwise reveals the hidden section.
    public func toggle() {
        setVisibility(visibility == .collapsed ? .revealed : .collapsed)
    }

    /// Clicking a boundary opens whatever is still beyond it, and collapses once there is
    /// nothing left — so the always-hidden section is reachable from the bar alone.
    private func revealFurtherOrCollapse() {
        let hasMoreToShow = visibility == .revealed && alwaysHiddenDivider != nil
        setVisibility(hasMoreToShow ? .fullyRevealed : .collapsed)
    }

    private func apply(_ visibility: MenuBarVisibility) {
        hiddenDivider?.isExpanded = !visibility.shows(.hidden)
        if !visibility.shows(.hidden) { hiddenDivider?.padding = 0 }
        alwaysHiddenDivider?.isExpanded = !visibility.shows(.alwaysHidden)
        iconItem?.button?.image = markImage(for: visibility)
    }

    /// The dot is filled while everything is put away and hollow while a section is open,
    /// so the icon reads as the button for whatever is revealed. Where hiding actually
    /// ends is the divider's own glyph, which may be several items further left.
    private func markImage(for visibility: MenuBarVisibility) -> NSImage? {
        visibility == .collapsed ? iconImage : iconOpenImage
    }

    private func applyPreferences(_ preferences: Preferences) {
        setIconVisible(preferences.showBouncerIcon)

        let hidesItems = preferences.enableMenuBarItems
        if !hidesItems { setVisibility(.collapsed) }
        setHiddenDividerEnabled(hidesItems)
        setAlwaysHiddenSectionEnabled(hidesItems && preferences.enableAlwaysHiddenSection)
        if !preferences.enableAlwaysHiddenSection, visibility == .fullyRevealed {
            setVisibility(.revealed)
        }
    }

    private func setHiddenDividerEnabled(_ isEnabled: Bool) {
        guard isEnabled == (hiddenDivider == nil) else { return }
        guard isEnabled else {
            hiddenDivider?.remove()
            hiddenDivider = nil
            return
        }

        let divider = ControlItem(
            autosaveName: StatusItemPosition.hiddenDividerName,
            position: StatusItemPosition.hiddenDivider,
            markerImage: dividerImage
        )
        divider.onClick = { [weak self] in self?.revealFurtherOrCollapse() }
        divider.keepsVisible = { [weak self] in self?.iconItem?.button?.window?.frame }
        divider.isExpanded = !visibility.shows(.hidden)
        hiddenDivider = divider
    }

    private func setAlwaysHiddenSectionEnabled(_ isEnabled: Bool) {
        guard isEnabled == (alwaysHiddenDivider == nil) else { return }
        guard isEnabled else {
            alwaysHiddenDivider?.remove()
            alwaysHiddenDivider = nil
            return
        }

        let divider = ControlItem(
            autosaveName: StatusItemPosition.alwaysHiddenDividerName,
            position: StatusItemPosition.alwaysHiddenDivider,
            markerImage: outerDividerImage
        )
        divider.onClick = { [weak self] in self?.setVisibility(.revealed) }
        divider.isExpanded = !visibility.shows(.alwaysHidden)
        alwaysHiddenDivider = divider
    }

    private func setIconVisible(_ isVisible: Bool) {
        guard isVisible == (iconItem == nil) else { return }
        guard isVisible else {
            iconMoves.map(NotificationCenter.default.removeObserver)
            iconMoves = nil
            iconItem.map(NSStatusBar.system.removeStatusItem)
            iconItem = nil
            return
        }

        StatusItemPosition.seed(StatusItemPosition.icon, for: StatusItemPosition.iconName)
        // The logo is wider than it is tall, so the item sizes to its image.
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = StatusItemPosition.iconName
        item.button?.image = markImage(for: visibility)
        item.button?.target = self
        item.button?.action = #selector(iconClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        iconItem = item
        // macOS 27 keeps the icon wherever the user drags it, left of the divider included, and
        // overflows it when the bar is full. Either way the divider has to look again.
        if #available(macOS 27, *) {
            iconMoves = NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification, object: item.button?.window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.hiddenDivider?.lookAgain() }
            }
        }
    }

    @objc private func iconClicked() {
        // Assigning `menu` permanently would make left clicks open it too, so attach
        // it only for the duration of this click.
        guard NSApp.currentEvent?.type == .rightMouseUp, let iconMenu else {
            onIconClick?()
            return
        }
        iconItem?.menu = iconMenu
        iconItem?.button?.performClick(nil)
        iconItem?.menu = nil
    }
}
