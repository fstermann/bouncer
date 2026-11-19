import CoreGraphics
import Foundation

/// Switches a display to another of its Spaces at once, without the slide.
///
/// Posts what a fast three-finger swipe sends the Dock: a Dock swipe's begin, change and end, each with
/// a gesture event behind it, one swipe per Space to cross, all in one burst. The smallest float in the
/// flag field makes the Dock skip its animation. Undocumented, taken from iss (github.com/joshuarli/iss),
/// checked on macOS 26; macOS 27 checks each swipe against an IOHID record, which `SwipePayload` adds.
/// SkyLight's calls are resolved at runtime: without them `go` returns `false` and the caller falls back.
enum SpaceSwitch {
    /// How many Spaces to cross, and which way, to get from `current` to `target` in `order`: positive
    /// to the right. `nil` when either is missing from `order`.
    static func steps(from current: UInt64, to target: UInt64, in order: [UInt64]) -> Int? {
        guard let from = order.firstIndex(of: current), let to = order.firstIndex(of: target) else { return nil }
        return to - from
    }

    private typealias Connection = @convention(c) () -> Int32
    private typealias CurrentSpace = @convention(c) (Int32, CFString) -> UInt64

    private struct Calls: @unchecked Sendable {
        let connection: Int32
        let currentSpace: CurrentSpace
    }

    private static let calls: Calls? = {
        guard let sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let connection = dlsym(sky, "SLSMainConnectionID"),
              let current = dlsym(sky, "SLSManagedDisplayGetCurrentSpace")
        else { return nil }
        return Calls(
            connection: unsafeBitCast(connection, to: Connection.self)(),
            currentSpace: unsafeBitCast(current, to: CurrentSpace.self)
        )
    }()

    /// How long each swipe may take to land before the switch is given up.
    private static let stepLimit: Duration = .milliseconds(300)

    /// Switches `display` (SkyLight's identifier) to `target`, crossing the Spaces of `order`, its Spaces
    /// in Mission Control's order. Returns whether it got there. Waits for the landing, so never on the main actor.
    static func go(to target: UInt64, on display: String, order: [UInt64]) -> Bool {
        guard let calls else { return false }
        let current = { calls.currentSpace(calls.connection, display as CFString) }
        guard let steps = steps(from: current(), to: target, in: order) else { return false }
        // All at once, faster the further they go, as InstantSpaceSwitcher does: waiting for each swipe
        // to land showed every Space on the way for a frame and took about 0.1 s per Space.
        for _ in 0..<abs(steps) { swipe(right: steps > 0, velocity: 400 * Double(abs(steps))) }
        let deadline = ContinuousClock.now + stepLimit * max(1, abs(steps))
        while current() != target {
            guard ContinuousClock.now < deadline else { return false }
            usleep(2000)
        }
        return true
    }

    private static func swipe(right: Bool, velocity: Double) {
        if SwipePayload.isNeeded {
            guard let events = SwipePayload.swipe(right: right) else { return }
            for event in events {
                guard let gesture = CGEvent(source: nil) else { return }
                gesture.setIntegerValueField(Field.type, value: Kind.gesture)
                event.post(tap: .cgSessionEventTap)
                gesture.post(tap: .cgSessionEventTap)
            }
            return
        }
        for phase in [Phase.began, Phase.changed, Phase.ended] {
            guard let dock = dockEvent(phase, right: right, velocity: velocity),
                  let gesture = CGEvent(source: nil)
            else { return }
            gesture.setIntegerValueField(Field.type, value: Kind.gesture)
            dock.post(tap: .cgSessionEventTap)
            gesture.post(tap: .cgSessionEventTap)
        }
    }

    private static func dockEvent(_ phase: Int64, right: Bool, velocity: Double) -> CGEvent? {
        guard let event = CGEvent(source: nil) else { return nil }
        event.setIntegerValueField(Field.type, value: Kind.dockControl)
        event.setIntegerValueField(Field.hidType, value: 23)
        event.setIntegerValueField(Field.phase, value: phase)
        let flag = right ? Float.leastNonzeroMagnitude : -Float.leastNonzeroMagnitude
        event.setIntegerValueField(Field.flags, value: Int64(Int32(bitPattern: flag.bitPattern)))
        event.setIntegerValueField(Field.motion, value: 1)
        event.setDoubleValueField(Field.scrollY, value: 0)
        event.setDoubleValueField(Field.zoomX, value: Double(Float.leastNonzeroMagnitude))
        if phase == Phase.ended {
            event.setDoubleValueField(Field.velocityX, value: right ? velocity : -velocity)
            event.setDoubleValueField(Field.velocityY, value: 0)
        }
        return event
    }

    private enum Kind {
        static let gesture: Int64 = 29
        static let dockControl: Int64 = 30
    }

    private enum Phase {
        static let began: Int64 = 1
        static let changed: Int64 = 2
        static let ended: Int64 = 4
    }

    // swiftlint:disable force_unwrapping
    private enum Field {
        static let type = CGEventField(rawValue: 55)!
        static let hidType = CGEventField(rawValue: 110)!
        static let scrollY = CGEventField(rawValue: 119)!
        static let motion = CGEventField(rawValue: 123)!
        static let velocityX = CGEventField(rawValue: 129)!
        static let velocityY = CGEventField(rawValue: 130)!
        static let phase = CGEventField(rawValue: 132)!
        static let flags = CGEventField(rawValue: 135)!
        static let zoomX = CGEventField(rawValue: 139)!
    }
    // swiftlint:enable force_unwrapping
}
