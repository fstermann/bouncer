import AppKit
import BouncerFoundation
import Settings

/// Translates user input and idle timeouts into visibility changes.
///
/// Every input source is installed only while the preference that needs it is on, so a
/// user who does not use hover reveal pays nothing for it.
@MainActor
public final class RevealController {
    private let manager: MenuBarManager
    private let settings: SettingsStore

    private var hoverMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var rehideTask: Task<Void, Never>?

    private var inputObservation: ObservationLoop?
    private var rehideObservation: ObservationLoop?

    public init(manager: MenuBarManager, settings: SettingsStore) {
        self.manager = manager
        self.settings = settings
    }

    public func start() {
        manager.onIconClick = { [weak manager] in manager?.toggle() }

        // `preferences` is one observable value, so either loop re-arms on any edit.
        // Reconfiguration is a handful of registrations, and edits are rare.
        inputObservation = ObservationLoop { [weak self] in
            self?.configureInputs()
        }
        rehideObservation = ObservationLoop { [weak self] in
            self?.scheduleRehide()
        }
    }

    // MARK: - Input

    private func configureInputs() {
        let preferences = settings.preferences

        setHoverMonitorEnabled(preferences.revealOnHover)
        setActivationObserverEnabled(preferences.autoRehide == .onFocusedAppChange)
    }

    private func setHoverMonitorEnabled(_ isEnabled: Bool) {
        guard isEnabled == (hoverMonitor == nil) else { return }
        guard isEnabled else {
            hoverMonitor.map(NSEvent.removeMonitor)
            hoverMonitor = nil
            return
        }
        hoverMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { _ in
            MainActor.assumeIsolated { self.handlePointerMoved() }
        }
    }

    private func handlePointerMoved() {
        guard manager.visibility == .collapsed,
              let screen = NSScreen.main,
              screen.frame.maxY - NSEvent.mouseLocation.y <= screen.menuBarHeight
        else { return }
        manager.setVisibility(.revealed)
    }

    private func setActivationObserverEnabled(_ isEnabled: Bool) {
        guard isEnabled == (activationObserver == nil) else { return }
        guard isEnabled else {
            if let activationObserver {
                NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            }
            activationObserver = nil
            return
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { self.manager.setVisibility(.collapsed) }
        }
    }

    // MARK: - Auto-rehide

    private func scheduleRehide() {
        let visibility = manager.visibility
        let autoRehide = settings.preferences.autoRehide

        rehideTask?.cancel()
        rehideTask = nil

        guard visibility != .collapsed, case .afterDelay(let seconds) = autoRehide else { return }
        rehideTask = Task { [weak manager] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            manager?.setVisibility(.collapsed)
        }
    }
}

extension NSScreen {
    /// Menu bar height, accounting for the notch on displays that have one.
    var menuBarHeight: CGFloat {
        safeAreaInsets.top > 0 ? safeAreaInsets.top : frame.maxY - visibleFrame.maxY
    }
}
