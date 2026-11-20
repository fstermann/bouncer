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
    /// Set for a bar the pointer opened at the notch, which goes once the pointer has left it, the
    /// way the Dock does, whatever "Hide again" says: at once well clear of it, else after a grace,
    /// so a slip below the band is taken back. The same tolerance as the notch's pages.
    var closesOnLeave = false
    private static let leaveGrace: Duration = .milliseconds(1500)
    /// How far below the bar the pointer can stray before it has plainly left.
    private static let reach: CGFloat = 80
    /// Set for a bar a page turned into, which the pointer may never have been over: on the page
    /// menu below it, or anywhere for a key. Leaving counts once the pointer has come up into it.
    var waitsForPointer = false
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

    /// The pointer has left the bar, `depth` below it: close once the delay is up, where there is one.
    func pointerLeft(for mode: AutoRehide, depth: CGFloat, onClose: @MainActor @escaping () -> Void) {
        let isWellClear = closesOnLeave && depth > Self.reach
        guard pending == nil || isWellClear, !waitsForPointer,
              let delay = isWellClear ? .zero : delay(for: mode)
        else { return }
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            onClose()
        }
    }

    private func delay(for mode: AutoRehide) -> Duration? {
        if closesOnLeave { return Self.leaveGrace }
        guard case .afterDelay(let seconds) = mode else { return nil }
        return .seconds(seconds)
    }

    /// Taken back before the close came due, or held off by a menu; `intoTheBar` once it is up there.
    func pointerReturned(intoTheBar: Bool = false) {
        pending?.cancel()
        pending = nil
        if intoTheBar { waitsForPointer = false }
    }

    func stop() {
        pointerReturned()
        waitsForPointer = false
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
    }
}
