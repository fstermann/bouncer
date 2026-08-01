import AppKit
import Settings

/// When the standalone bar puts itself away.
///
/// "Hide again" governs the bar as well as the menu bar reveal: the delay the user set is the
/// delay the bar waits once the pointer has left it, the mode that closes on an app change
/// closes the bar on one too, and `never` leaves the bar up until it is clicked away. Whether
/// closing is allowed at all — a menu hanging open under the bar, a handover in flight — is
/// the caller's to decide, and it decides again when the close comes due.
///
/// Nothing is installed while the bar is down: `start` on the way up, `stop` on the way down.
@MainActor
final class BarClosing {
    private var pending: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?

    /// Watches for another app taking over, in the one mode that closes on it.
    func start(for mode: AutoRehide, onClose: @MainActor @escaping () -> Void) {
        guard mode == .onFocusedAppChange else { return }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { onClose() }
        }
    }

    /// The pointer has left the bar: close once the delay is up, where there is one.
    func pointerLeft(for mode: AutoRehide, onClose: @MainActor @escaping () -> Void) {
        guard pending == nil, case .afterDelay(let seconds) = mode else { return }
        pending = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            onClose()
        }
    }

    /// Taken back before the close came due.
    func pointerReturned() {
        pending?.cancel()
        pending = nil
    }

    func stop() {
        pointerReturned()
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
    }
}
