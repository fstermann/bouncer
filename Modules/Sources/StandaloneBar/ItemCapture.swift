import BouncerFoundation
import CoreGraphics
import Observation

/// Pictures of the status items the standalone bar replicates.
///
/// One picture of the whole section, cut up per item, taken as the bar opens. Not a stream,
/// and that is the whole point: a replica is a still, so an item that changes while the bar is
/// open — a clock, a badge arriving — keeps the face it had when it opened. The bar is opened,
/// used and dismissed, so it holds that face for seconds at a time.
///
/// Taken while the section is still parked off the display, before it is revealed, which is
/// only possible through `SkyLightCapture`: ScreenCaptureKit cannot reach a window outside the
/// display bounds, and every ScreenCaptureKit capture inserts the recording indicator into the
/// bar, shifting the very items being replicated.
///
/// One call for the whole section rather than one per item. The cost is per call — thirteen
/// items cost about what one does — and cutting the result up is free.
@MainActor
@Observable
public final class ItemCapture {
    /// The picture of each item, keyed by window ID.
    public private(set) var images: [UInt32: CGImage] = [:]

    public init() {}

    /// Whether pictures can be taken at all on this system.
    public static var isAvailable: Bool { SkyLightCapture.isAvailable }

    /// Photographs every item where it currently sits.
    ///
    /// - Parameter items: the items to photograph, with the frames they hold *now*. The crop
    ///   maths is relative to those frames, so a stale one cuts the wrong part of the picture.
    public func capture(_ items: [MenuBarItem]) {
        cut(Self.composite(of: items), into: items)
    }

    /// The same, once a menu bar that is fading in has finished: what the bar opens with, since
    /// in a full screen space the pointer arriving at the top is what starts the fade.
    public func captureOnceDrawn(_ items: [MenuBarItem]) async {
        cut(await Self.photograph(items), into: items)
    }

    private func cut(_ picture: CGImage?, into items: [MenuBarItem]) {
        images.removeAll()
        guard let first = items.first else { return }

        let union = items.dropFirst().reduce(first.frame) { $0.union($1.frame) }
        guard union.width > 0, let section = picture else {
            Log.menuBar.error("Standalone bar: the section could not be photographed")
            return
        }

        // The capture is at backing-store resolution, so its pixels are a scaled copy of the
        // rect it covers. Derived rather than assumed: it is 2x on every display Bouncer has
        // been run on, but the crops go wrong silently if that ever stops being true.
        let scale = CGFloat(section.width) / union.width
        for item in items {
            let crop = CGRect(
                x: (item.frame.minX - union.minX) * scale,
                y: (item.frame.minY - union.minY) * scale,
                width: item.frame.width * scale,
                height: item.frame.height * scale
            )
            if let image = section.cropping(to: crop) { images[item.windowID] = image }
        }
    }

    /// The section once it is fully drawn.
    ///
    /// In a full screen space the menu bar fades in as the pointer reaches it, and its items are
    /// photographed as they are drawn: measured at 57% opacity as the pointer arrived, and fully
    /// drawn some 50 ms later. A section that is fully opaque nowhere is still fading, so it is
    /// photographed again, a frame at a time, up to a bound. Out of full screen the first picture
    /// is already drawn and nothing waits.
    private static func photograph(_ items: [MenuBarItem]) async -> CGImage? {
        var section = composite(of: items)
        for _ in 0..<fadeLimit {
            guard let picture = section, !CapturedImage.isFullyDrawn(picture) else { break }
            try? await Task.sleep(for: .milliseconds(16))
            section = composite(of: items)
        }
        return section
    }

    private static func composite(of items: [MenuBarItem]) -> CGImage? {
        guard !items.isEmpty else { return nil }
        return SkyLightCapture.composite(of: items.map(\.windowID), options: [.boundsIgnoreFraming, .bestResolution])
    }

    /// Frames to wait for a fading menu bar: comfortably past the fade, short enough that a
    /// section with no fully opaque pixel anywhere costs a third of a second, not a stall.
    private static let fadeLimit = 20

    /// Drops the pictures. Nothing is running, so there is nothing else to stop.
    public func stop() {
        images.removeAll()
    }
}
