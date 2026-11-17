import ApplicationServices
import CoreGraphics

/// Lays a deck's windows side by side.
enum Tiling {
    /// `count` frames filling `area` side by side, in equal columns of whole points, with `gap`
    /// between them. Four or more windows fill two rows, the top row taking the odd one.
    static func frames(count: Int, in area: CGRect, gap: CGFloat = 8) -> [CGRect] {
        guard count > 0 else { return [] }
        let rows = count >= 4 ? 2 : 1
        let perRow = [Int((Double(count) / Double(rows)).rounded(.up)), count / rows]
        let height = ((area.height - gap * CGFloat(rows - 1)) / CGFloat(rows)).rounded(.down)
        var frames: [CGRect] = []
        for row in 0..<rows {
            let columns = row == 0 ? perRow[0] : count - perRow[0]
            let width = ((area.width - gap * CGFloat(columns - 1)) / CGFloat(columns)).rounded(.down)
            for column in 0..<columns {
                frames.append(CGRect(
                    x: (area.minX + CGFloat(column) * (width + gap)).rounded(),
                    y: (area.minY + CGFloat(row) * (height + gap)).rounded(),
                    width: width, height: height
                ))
            }
        }
        return frames
    }

    /// Moves and sizes each window to its frame, in the window server's coordinates.
    ///
    /// Accessibility calls block, so this is never called from the main actor.
    static func apply(_ frames: [(WindowInfo, CGRect)]) {
        for (window, frame) in frames {
            guard let element = WindowFocus.element(for: window) else { continue }
            var origin = frame.origin
            var size = frame.size
            // Size, then position, then size again: an app may refuse a size that would not fit where
            // the window still is, or move a window that would not fit at its new size.
            if let value = AXValueCreate(.cgSize, &size) {
                AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
            }
            if let value = AXValueCreate(.cgPoint, &origin) {
                AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
            }
            if let value = AXValueCreate(.cgSize, &size) {
                AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
            }
        }
    }
}
