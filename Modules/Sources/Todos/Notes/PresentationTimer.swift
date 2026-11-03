import Foundation

/// A countdown or a stopwatch for a talk. Pure over dates, so its phases are tested without a clock.
struct PresentationTimer: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case countdown(TimeInterval)
        case stopwatch
    }

    /// Drawn plain while running, in orange for a countdown's last minute, and in red once it is over.
    enum Phase: Equatable, Sendable {
        case running, ending, over
    }

    let kind: Kind
    let start: Date

    static let warning: TimeInterval = 60

    /// When a countdown reaches zero; `nil` for a stopwatch.
    var end: Date? {
        guard case .countdown(let length) = kind else { return nil }
        return start.addingTimeInterval(length)
    }

    func phase(at now: Date) -> Phase {
        guard let end else { return .running }
        if now >= end { return .over }
        return now >= end.addingTimeInterval(-Self.warning) ? .ending : .running
    }

    /// When the phase next changes after `now`, to redraw then; `nil` once it no longer will.
    func nextChange(after now: Date) -> Date? {
        guard let end else { return nil }
        return [end.addingTimeInterval(-Self.warning), end].first { $0 > now }
    }
}
