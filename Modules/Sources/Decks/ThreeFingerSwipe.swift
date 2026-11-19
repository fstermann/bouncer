import AppKit

/// Tells a three-finger swipe up or down from the trackpad's touches.
///
/// A swipe is a run of frames with exactly three fingers down; it counts once the fingers' average height
/// has moved `travel` since the run began. Heights are the trackpad's, 0 at the bottom edge to 1 at the top.
struct SwipeDetector {
    enum Direction { case up, down }

    /// How far the fingers travel, as a share of the trackpad's height. Swipes up measured on a built-in
    /// trackpad rose 0.16 to 0.27; a three-finger rest drifts far less.
    static let travel: Double = 0.12

    private var start: Double?
    private var fired = false

    /// Takes one frame's finger heights; returns the direction of the swipe this frame completes, if any.
    mutating func feed(_ heights: [Double]) -> Direction? {
        guard heights.count == 3 else {
            start = nil
            fired = false
            return nil
        }
        let height = heights.reduce(0, +) / 3
        guard let start else {
            self.start = height
            return nil
        }
        guard !fired, abs(height - start) >= Self.travel else { return nil }
        fired = true
        return height > start ? .up : .down
    }
}

/// Listens to the trackpad's touches while the swipe is on, and reports a three-finger swipe up or down.
///
/// A listen-only event tap on gesture events, which Accessibility allows. It leaves the Dock's own swipe
/// events alone: tapping those stops an auto-hidden Dock from showing on hover.
@MainActor
final class ThreeFingerSwipe {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var detector = SwipeDetector()
    private let onSwipe: @MainActor (SwipeDetector.Direction) -> Void

    init(onSwipe: @escaping @MainActor (SwipeDetector.Direction) -> Void) {
        self.onSwipe = onSwipe
    }

    /// Starts listening. Returns whether the tap could be made, which needs Accessibility.
    func start() -> Bool {
        stop()
        // 29: NSEvent.EventType.gesture, the trackpad's touches; CGEventType has no name for it.
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly, eventsOfInterest: 1 << 29,
            callback: { _, type, event, info in
                if let info {
                    let watcher = Unmanaged<ThreeFingerSwipe>.fromOpaque(info).takeUnretainedValue()
                    MainActor.assumeIsolated { watcher.handle(type, event) }
                }
                return Unmanaged.passUnretained(event)
            },
            // Unretained: the controller keeps this object and stops it before letting go.
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        detector = SwipeDetector()
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard let touches = NSEvent(cgEvent: event)?.allTouches() else { return }
        let heights = touches.filter { $0.phase != .ended && $0.phase != .cancelled }
            .map { Double($0.normalizedPosition.y) }
        if let direction = detector.feed(heights) { onSwipe(direction) }
    }
}
