import AppKit
import ApplicationServices

/// Watches one app for its menus opening and closing.
///
/// A menu opens from the real item, a row above the bar, and lands on top of the replicas.
/// Nothing there can be clicked while it is up, so the bar steps back visually rather than
/// pretending otherwise.
///
/// Both signals come from the item's own application element, and cover the plain menus and
/// the panels some apps put up in their place — the two behave differently in every other
/// respect, including whether they can be moved.
///
/// Installed when a replica is pressed and removed when its menu closes, so nothing is
/// observing between clicks.
@MainActor
final class MenuWatcher {
    private var observer: AXObserver?
    private var onChange: ((Bool) -> Void)?

    /// Reports `true` when a menu of `pid` opens and `false` when one closes.
    func watch(pid: pid_t, onChange: @escaping (Bool) -> Void) {
        stop()

        var created: AXObserver?
        guard AXObserverCreate(pid, Self.handle, &created) == .success, let created else { return }

        let app = AXUIElementCreateApplication(pid)
        let context = Unmanaged.passUnretained(self).toOpaque()
        for notification in [kAXMenuOpenedNotification, kAXMenuClosedNotification] {
            AXObserverAddNotification(created, app, notification as CFString, context)
        }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(created), .defaultMode)

        observer = created
        self.onChange = onChange
    }

    func stop() {
        if let observer {
            CFRunLoopRemoveSource(
                CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode
            )
        }
        observer = nil
        onChange = nil
    }

    /// Runs on the run loop the source was added to, which is the main one.
    private static let handle: AXObserverCallback = { _, _, notification, context in
        guard let context else { return }
        let watcher = Unmanaged<MenuWatcher>.fromOpaque(context).takeUnretainedValue()
        let isOpen = notification as String == kAXMenuOpenedNotification
        MainActor.assumeIsolated { watcher.onChange?(isOpen) }
    }
}
