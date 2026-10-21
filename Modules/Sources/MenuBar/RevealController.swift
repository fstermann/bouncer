import AppKit
import BouncerFoundation
import Settings

/// Translates user input and idle timeouts into visibility changes.
///
/// Every input source is installed only while the preference that needs it is on, so a
/// user who does not use hover reveal pays nothing for it.
@MainActor
public final class RevealController {
    /// What the pointer entering the menu bar reveals. Left alone it walks the menu bar open;
    /// the app layer replaces it where a reveal means something else, the way `onIconClick`
    /// is replaced — whether the hidden section shows in the bar or in one of Bouncer's own is
    /// a preference this module has no business knowing about.
    public var onHoverReveal: (@MainActor () -> Void)?

    private let manager: MenuBarManager
    private let settings: SettingsStore

    private var hoverMonitor: Any?
    /// The same watch over Bouncer's own windows, which a global monitor never hears from. The
    /// collapsed divider is one of them, stretched across the menu bar and the notch.
    private var localHoverMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var rehideTask: Task<Void, Never>?
    /// The hover delay running out, started when the pointer arrives where it reveals.
    private var pendingReveal: Task<Void, Never>?

    private var inputObservation: ObservationLoop?
    private var rehideObservation: ObservationLoop?
    private var settledObservation: ObservationLoop?

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

        setHoverMonitorEnabled(preferences.revealOnHover || preferences.revealNearNotch)
        setActivationObserverEnabled(preferences.autoRehide == .onFocusedAppChange)
    }

    private func setHoverMonitorEnabled(_ isEnabled: Bool) {
        guard isEnabled == (hoverMonitor == nil) else { return }
        guard isEnabled else {
            hoverMonitor.map(NSEvent.removeMonitor)
            hoverMonitor = nil
            localHoverMonitor.map(NSEvent.removeMonitor)
            localHoverMonitor = nil
            pendingReveal?.cancel()
            pendingReveal = nil
            settledObservation?.cancel()
            settledObservation = nil
            return
        }
        hoverMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { _ in
            MainActor.assumeIsolated { self.handlePointerMoved() }
        }
        localHoverMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { event in
            MainActor.assumeIsolated { self.handlePointerMoved() }
            return event
        }
        // The pointer may have come back while the section or the bar was still going away, and
        // moves made then were turned down. Like the Dock, it reveals again without another move.
        settledObservation = ObservationLoop { [weak self] in
            self?.handlePointerMoved()
        }
    }

    /// Reveals once the pointer has rested where it reveals for the hover delay, the way the Dock
    /// shows. Leaving before then calls it off.
    private func handlePointerMoved() {
        // Both read first, so the observation that re-runs this hears either change.
        let isSettled = manager.visibility == .collapsed && !manager.isRevealHeld
        guard hoverMonitor != nil, isSettled, isPointerRevealing else {
            pendingReveal?.cancel()
            pendingReveal = nil
            return
        }
        guard pendingReveal == nil else { return }
        let delay = hoverDelay
        pendingReveal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            pendingReveal = nil
            guard manager.visibility == .collapsed, isPointerRevealing else { return }
            guard let onHoverReveal else {
                manager.setVisibility(.revealed)
                return
            }
            onHoverReveal()
        }
    }

    private var hoverDelay: TimeInterval {
        switch settings.preferences.hoverDelay {
        case .matchDock: DockDelay.current
        case .seconds(let seconds): seconds
        }
    }

    private var isPointerRevealing: Bool {
        NSScreen.main.map(isRevealing(on:)) ?? false
    }

    /// Anywhere in the menu bar, or only near the notch when that is the one switched on.
    private func isRevealing(on screen: NSScreen) -> Bool {
        let point = NSEvent.mouseLocation
        guard !settings.preferences.revealOnHover else {
            return screen.frame.maxY - point.y <= screen.menuBarHeight
        }
        let notch = DisplayNotch.range(
            left: screen.auxiliaryTopLeftArea, right: screen.auxiliaryTopRightArea, screen: screen.frame
        ).range
        return DisplayNotch.reveals(at: point, notch: notch, screen: screen.frame, menuBarHeight: screen.menuBarHeight)
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
            MainActor.assumeIsolated {
                guard !self.manager.isRevealHeld else { return }
                self.manager.setVisibility(.collapsed)
            }
        }
    }

    // MARK: - Auto-rehide

    private func scheduleRehide() {
        let visibility = manager.visibility
        let autoRehide = settings.preferences.autoRehide

        rehideTask?.cancel()
        rehideTask = nil

        guard !manager.isRevealHeld,
              visibility != .collapsed,
              case .afterDelay(let seconds) = autoRehide
        else { return }
        rehideTask = Task { [weak manager] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            manager?.setVisibility(.collapsed)
        }
    }
}

extension NSScreen {
    /// Menu bar height, accounting for the notch on displays that have one.
    public var menuBarHeight: CGFloat {
        safeAreaInsets.top > 0 ? safeAreaInsets.top : frame.maxY - visibleFrame.maxY
    }
}
