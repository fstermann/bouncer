import CoreGraphics

/// Where a window dragged onto another display's overview lands, in the window server's coordinates.
enum DisplayMove {
    /// `frame` moved from the display area `source` to `target`, at the same place relative to the area,
    /// shrunk to fit it, on whole points.
    static func frame(_ frame: CGRect, from source: CGRect, to target: CGRect) -> CGRect {
        let width = min(frame.width, target.width).rounded(.down)
        let height = min(frame.height, target.height).rounded(.down)
        // How far along the room left around the window it sat: 0 at one edge, 1 at the other.
        func share(_ offset: CGFloat, room: CGFloat) -> CGFloat {
            room > 0 ? min(max(offset / room, 0), 1) : 0.5
        }
        let across = share(frame.minX - source.minX, room: source.width - frame.width)
        let down = share(frame.minY - source.minY, room: source.height - frame.height)
        return CGRect(
            x: target.minX + (across * (target.width - width)).rounded(),
            y: target.minY + (down * (target.height - height)).rounded(),
            width: width, height: height
        )
    }

    /// The index of the display among `frames` that holds `point`.
    static func display(at point: CGPoint, among frames: [CGRect]) -> Int? {
        frames.firstIndex { $0.contains(point) }
    }

    /// `windows` grouped by the Space each is on, in the given order, with whether that Space is off
    /// screen and so must be switched to first. The current Space's group, and any window of no known
    /// Space, come first.
    static func bySpace(
        _ windows: [WindowInfo], spaces: [CGWindowID: SpaceInfo]
    ) -> [(windows: [WindowInfo], isElsewhere: Bool)] {
        struct Group {
            let space: UInt64?
            var windows: [WindowInfo]
            let isElsewhere: Bool
        }
        var groups: [Group] = []
        for window in windows {
            let space = spaces[window.id]
            if let index = groups.firstIndex(where: { $0.space == space?.id }) {
                groups[index].windows.append(window)
            } else {
                groups.append(Group(space: space?.id, windows: [window], isElsewhere: space?.isCurrent == false))
            }
        }
        return (groups.filter { !$0.isElsewhere } + groups.filter(\.isElsewhere)).map { ($0.windows, $0.isElsewhere) }
    }
}
