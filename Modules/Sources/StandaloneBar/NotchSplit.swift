import CoreGraphics

/// How macOS 27's bar shares the revealed section between the two sides of the notch.
///
/// Items there sit only right of the notch, packed against the divider, and those that do not fit
/// go behind the chevron, which draws them left of it. Widening the divider is what moves items
/// across, so its extra width is the one thing chosen here. Measured in SPIKES.md.
enum NotchSplit {
    /// How the section lay when last open, which the next open goes by before anything is revealed.
    struct Layout: Equatable {
        /// Both sides' items together, the chevron left out.
        let width: CGFloat
        /// The band's ends, in window-server x.
        let reach: ClosedRange<CGFloat>
        let chevron: CGRect?
        /// The section's end it was read against: a section that moved lays out differently.
        let end: CGFloat
    }

    /// From the notch to the first item right of it while the chevron is there: the margin macOS
    /// keeps, then the chevron. Measured on macOS 27.2.
    static let leadRight: CGFloat = 62
    /// From the section's last item to its end: the gap before the divider, and the divider.
    static let tailRight: CGFloat = 25
    /// How far the black band reaches past the outermost items.
    static let bandPadding: CGFloat = 8

    /// The divider's extra width that leaves room right of the notch for half of `hiddenWidth`.
    static func shift(for hiddenWidth: CGFloat, endingAt end: CGFloat, notch: ClosedRange<CGFloat>) -> CGFloat {
        let room = end - tailRight - notch.upperBound - leadRight
        return max(0, room - hiddenWidth / 2)
    }

    /// The width the revealed section takes on both sides together, from `frames` read while it is
    /// revealed, the chevron left out. `nil` when none of it is in the bar.
    static func hiddenWidth(of frames: [CGRect], notch: ClosedRange<CGFloat>, end: CGFloat) -> CGFloat? {
        let left = leftOfNotch(frames, notch)
        let right = rightOfNotch(frames, notch, end)
        guard !left.isEmpty || !right.isEmpty else { return nil }
        return span(of: left) + span(of: right)
    }

    /// The stretch of bar the black band covers: the notch, and the section's items either side.
    static func band(over frames: [CGRect], notch: ClosedRange<CGFloat>, end: CGFloat) -> ClosedRange<CGFloat> {
        let section = leftOfNotch(frames, notch) + rightOfNotch(frames, notch, end)
        let lower = (section.map(\.minX).min() ?? .infinity) - bandPadding
        let upper = (section.map(\.maxX).max() ?? -.infinity) + bandPadding
        return min(lower, notch.lowerBound)...max(upper, notch.upperBound)
    }

    /// What hides the chevron: from the notch to just past it, the bar's full height. Pressed, it
    /// takes the left side away and leaves the band over the app menus.
    static func shade(over chevron: CGRect, notch: ClosedRange<CGFloat>) -> CGRect {
        CGRect(x: notch.upperBound, y: 0, width: chevron.maxX + shadePadding - notch.upperBound, height: chevron.maxY)
    }

    /// Less than half the gap macOS keeps between the chevron and the next item.
    static let shadePadding: CGFloat = 2

    /// Only the open chevron puts items there. One it had no room for sits above the display.
    private static func leftOfNotch(_ frames: [CGRect], _ notch: ClosedRange<CGFloat>) -> [CGRect] {
        frames.filter { $0.minY >= 0 && $0.maxX <= notch.lowerBound }
    }

    private static func rightOfNotch(_ frames: [CGRect], _ notch: ClosedRange<CGFloat>, _ end: CGFloat) -> [CGRect] {
        frames.filter { $0.minY >= 0 && $0.minX >= notch.upperBound && $0.maxX <= end }
    }

    private static func span(of frames: [CGRect]) -> CGFloat {
        guard let lower = frames.map(\.minX).min(), let upper = frames.map(\.maxX).max() else { return 0 }
        return upper - lower
    }
}
