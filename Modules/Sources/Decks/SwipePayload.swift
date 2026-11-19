import CoreGraphics
import Foundation

/// The Dock swipe macOS 27 accepts: it checks a posted swipe against the IOHID record a real trackpad
/// attaches, so each event carries one, appended to its serialized form.
///
/// Layout, progress and sign from noswoosh (github.com/mmathys/noswoosh, MIT), which reverse-engineered
/// them from iss. Untested here: only checked against macOS 26, which ignores the record.
enum SwipePayload {
    static let isNeeded = ProcessInfo.processInfo.isOperatingSystemAtLeast(
        OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)
    )

    /// The begin, change and end of one swipe, or `nil` if any fails to build: a partial swipe leaves the
    /// Dock mid-gesture on a blank Space.
    static func swipe(right: Bool) -> [CGEvent]? {
        var events: [CGEvent] = []
        for phase in [Phase.began, Phase.changed, Phase.ended] {
            guard let event = dockEvent(phase, right: right).flatMap(attach) else { return nil }
            events.append(event)
        }
        return events
    }

    private static func dockEvent(_ phase: Int64, right: Bool) -> CGEvent? {
        guard let event = CGEvent(source: nil) else { return nil }
        // Posted swipes read the other way round with Natural scrolling off.
        let natural = CFPreferencesCopyAppValue("com.apple.swipescrolldirection" as CFString,
                                                kCFPreferencesAnyApplication) as? Bool ?? true
        let sign = (right ? -1.0 : 1.0) * (natural ? 1 : -1)
        event.setIntegerValueField(Field.type, value: 30)
        event.setIntegerValueField(Field.hidType, value: 23)
        event.setIntegerValueField(Field.phase, value: phase)
        // Not near zero: 1e-4 left the destination undrawn on 27.0.1 in up to 13 of 20 switches; 0.1
        // landed every time and still cuts in one frame. The fling on the end is what commits.
        event.setDoubleValueField(Field.progress, value: 0.1 * sign)
        event.setIntegerValueField(Field.motion, value: 1)
        event.setDoubleValueField(Field.positionX, value: 0.1)
        if phase == Phase.ended { event.setDoubleValueField(Field.velocityX, value: 9999 * sign) }
        return event
    }

    /// `event` with its IOHID record appended under field 0x106D, which no setter writes.
    private static func attach(to event: CGEvent) -> CGEvent? {
        guard let data = event.data else { return nil }
        var bytes = [UInt8](data as Data)
        guard bytes.starts(with: [0, 0, 0, 2]) else { return nil }
        let record = record(of: event)
        bytes += [UInt8(record.count >> 8), UInt8(record.count & 0xFF), 0x10, 0x6D] + record
        return CGEvent(withDataAllocator: nil, data: Data(bytes) as CFData)
    }

    /// A queue header, a fluid touch gesture and, at the end or in motion, a velocity, little endian.
    private static func record(of event: CGEvent) -> [UInt8] {
        let phase = event.getIntegerValueField(Field.phase)
        let velocityX = event.getDoubleValueField(Field.velocityX)
        let velocityY = event.getDoubleValueField(Field.velocityY)
        let hasVelocity = velocityX != 0 || velocityY != 0 || phase == Phase.ended
        var bytes: [UInt8] = []
        func put<Value: FixedWidthInteger>(_ value: Value) {
            withUnsafeBytes(of: value.littleEndian) { bytes.append(contentsOf: $0) }
        }
        put(event.timestamp != 0 ? event.timestamp : mach_absolute_time())
        put(UInt64(0))
        put(UInt32(0))
        put(UInt32(0))
        put(UInt32(hasVelocity ? 2 : 1))
        put(UInt32(40))
        put(UInt32(23))
        put((UInt32(truncatingIfNeeded: phase) & 0xFF) << 24)
        put(UInt32(0))
        put(fixed(event.getDoubleValueField(Field.positionX)))
        put(fixed(event.getDoubleValueField(Field.positionY)))
        put(Int32(0))
        put(UInt32(truncatingIfNeeded: event.getIntegerValueField(Field.mask)))
        put(UInt16(truncatingIfNeeded: event.getIntegerValueField(Field.motion)))
        put(UInt16(3))
        put(fixed(event.getDoubleValueField(Field.progress)))
        if hasVelocity {
            put(UInt32(28))
            put(UInt32(9))
            put(UInt32(0))
            put(UInt32(1))
            put(fixed(velocityX))
            put(fixed(velocityY))
            put(Int32(0))
        }
        return bytes
    }

    /// 16.16 fixed point, never rounding a nonzero value to 0, which would lose its sign.
    private static func fixed(_ value: Double) -> Int32 {
        let result = Int32(truncatingIfNeeded: Int64(value * 65536))
        guard result == 0, value != 0 else { return result }
        return value > 0 ? 1 : -1
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
        static let mask = CGEventField(rawValue: 115)!
        static let motion = CGEventField(rawValue: 123)!
        static let progress = CGEventField(rawValue: 124)!
        static let positionX = CGEventField(rawValue: 125)!
        static let positionY = CGEventField(rawValue: 126)!
        static let velocityX = CGEventField(rawValue: 129)!
        static let velocityY = CGEventField(rawValue: 130)!
        static let phase = CGEventField(rawValue: 132)!
    }
    // swiftlint:enable force_unwrapping
}
