import AppKit
import BouncerFoundation
import Observation
import Settings

/// Owns the menu bar's structure: the dividers that define the sections, Bouncer's own
/// status item, and which sections are currently on screen.
///
/// Deliberately knows nothing about *why* visibility changes — hotkeys, hover and
/// auto-rehide live in `RevealController`.
@MainActor
@Observable
public final class MenuBarManager {
    public private(set) var visibility: MenuBarVisibility = .collapsed

    /// Widens the dividers so the user can Cmd-drag items between sections.
    public var isEditingLayout = false {
        didSet { applyEditing() }
    }

    /// Bouncer's own status item, when `showBouncerIcon` is enabled. Assign a `menu`
    /// to it from the app layer; left clicks toggle visibility.
    public private(set) var iconItem: NSStatusItem?

    /// Invoked on a left click of Bouncer's icon.
    public var onIconClick: (@MainActor () -> Void)?

    /// Shown on a right click of Bouncer's icon.
    public var iconMenu: NSMenu?

    private let settings: SettingsStore
    private let hiddenDivider: ControlItem
    private let alwaysHiddenDivider: ControlItem
    private var observation: ObservationLoop?

    public init(settings: SettingsStore) {
        self.settings = settings
        hiddenDivider = ControlItem(autosaveName: "bouncer.divider.hidden", symbolName: "chevron.left")
        alwaysHiddenDivider = ControlItem(
            autosaveName: "bouncer.divider.alwaysHidden",
            symbolName: "chevron.left.2"
        )

        observation = ObservationLoop { [weak self] in
            self?.applyPreferences(self?.settings.preferences ?? Preferences())
        }
        apply(visibility)
    }

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

    /// The items macOS currently reports, annotated with the section they fall into.
    ///
    /// Returns `nil` while a divider is expanded: an off-screen divider has no
    /// meaningful x-position to classify against, so ask for the layout only while
    /// `.fullyRevealed` (which `isEditingLayout` guarantees).
    public func currentLayout() -> [(item: MenuBarItem, section: MenuBarSection)]? {
        guard visibility == .fullyRevealed, let hiddenFrame = hiddenDivider.frame else { return nil }
        return MenuBarLayout.classify(
            items: MenuBarItemScanner.scan(),
            hiddenDividerMinX: hiddenFrame.minX,
            alwaysHiddenDividerMinX: settings.preferences.enableAlwaysHiddenSection
                ? alwaysHiddenDivider.frame?.minX
                : nil
        )
    }

    private func apply(_ visibility: MenuBarVisibility) {
        hiddenDivider.isExpanded = !visibility.shows(.hidden)
        alwaysHiddenDivider.isExpanded = !visibility.shows(.alwaysHidden)
    }

    private func applyEditing() {
        hiddenDivider.isEditing = isEditingLayout
        alwaysHiddenDivider.isEditing = isEditingLayout
        if isEditingLayout {
            setVisibility(.fullyRevealed)
        }
    }

    private func applyPreferences(_ preferences: Preferences) {
        setIconVisible(preferences.showBouncerIcon)

        if !preferences.enableAlwaysHiddenSection, visibility == .fullyRevealed {
            setVisibility(.revealed)
        }
    }

    private func setIconVisible(_ isVisible: Bool) {
        guard isVisible == (iconItem == nil) else { return }
        guard isVisible else {
            iconItem.map(NSStatusBar.system.removeStatusItem)
            iconItem = nil
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "bouncer.icon"
        item.button?.image = NSImage(systemSymbolName: "chevron.left.2", accessibilityDescription: "Bouncer")
        item.button?.target = self
        item.button?.action = #selector(iconClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        iconItem = item
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
