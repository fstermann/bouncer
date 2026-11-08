import AppKit

/// Watches where the pointer goes once it is outside a panel: back in stops the watch, well clear
/// or out for the whole grace period calls `onLeave`. Its monitors are installed only between
/// leaving and coming back.
@MainActor
final class LeaveWatch {
    private var monitors: [Any] = []
    private var grace: Task<Void, Never>?

    private static var gracePeriod: Duration { .milliseconds(1500) }
    /// How far outside the panel the pointer can stray before it has plainly left.
    private static var reach: CGFloat { 80 }

    /// - Parameter area: where the panel rests, in AppKit screen coordinates, read as the pointer moves.
    func start(around area: @escaping @MainActor () -> CGRect, onLeave: @escaping @MainActor () -> Void) {
        guard monitors.isEmpty else { return }
        grace = Task { [weak self] in
            try? await Task.sleep(for: Self.gracePeriod)
            guard !Task.isCancelled else { return }
            self?.stop()
            onLeave()
        }
        let check: @MainActor () -> Void = { [weak self] in
            guard let self, Self.isWellClear(NSEvent.mouseLocation, of: area()) else { return }
            stop()
            onLeave()
        }
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { _ in MainActor.assumeIsolated(check) },
            NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { event in
                MainActor.assumeIsolated(check)
                return event
            }
        ].compactMap(\.self)
    }

    func stop() {
        grace?.cancel()
        grace = nil
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }

    private static func isWellClear(_ point: CGPoint, of area: CGRect) -> Bool {
        let dx = max(area.minX - point.x, 0, point.x - area.maxX)
        let dy = max(area.minY - point.y, 0, point.y - area.maxY)
        return hypot(dx, dy) > reach
    }
}
