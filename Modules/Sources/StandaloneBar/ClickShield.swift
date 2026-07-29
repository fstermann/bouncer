import AppKit

/// Swallows clicks on the stretch of bar the section was revealed into.
///
/// The items are not moved to hide them, only painted over, so they stay exactly as
/// clickable as they were. Without this, a click where one of them used to sit opens its menu
/// out of what reads as empty menu bar — the item invisible, its menu not.
///
/// The cover cannot do this itself. It spans the whole bar, so a cover that took clicks would
/// swallow them for every visible item and the app menus with them; it has to let everything
/// through, and this takes back the one stretch that should not.
///
/// Nothing is drawn. The window exists to be hit first and do nothing about it.
@MainActor
final class ClickShield {
    private var window: BarWindow?

    /// The shield's own window, so a capture of the bar can leave it out.
    var windowID: UInt32? { window.map { UInt32($0.windowNumber) } }

    /// Covers `rect`, in window-server coordinates.
    func show(over rect: CGRect) {
        let shield = window ?? make(rect)
        window = shield
        shield.setFrame(cgFrame: rect)
        shield.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
    }

    private func make(_ rect: CGRect) -> BarWindow {
        // Above the cover, which is itself a level above the items. Order only decides which
        // window is hit; there is nothing here to see in front of anything.
        BarWindow(frame: rect, level: NSWindow.Level(rawValue: BarWindow.statusLevel.rawValue + 2))
    }
}
