import BouncerFoundation
import CoreGraphics
import Observation

/// Pictures of the status items the standalone bar replicates.
///
/// One still per item, taken as the bar opens. Not a stream, and that is the whole point: an
/// item that changes while the bar is open — a clock, a badge arriving — keeps the face it had
/// when it opened. The bar is opened, used and dismissed, so it holds that face for seconds.
///
/// A status item must be on-screen and settled before it has pixels worth keeping. Callers that
/// start with a parked section reveal it behind a cover, wait for WindowServer to draw it, take
/// this still, and then either keep it revealed or put it away again.
///
/// The hardware window-list call returns one union-sized image, which is cropped back into the
/// items. The older composite call remains a fallback for older systems. Both paths can return
/// transparent pixels for parked status items.
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
    @discardableResult
    public func capture(_ items: [MenuBarItem]) -> Bool {
        images.removeAll()
        guard !items.isEmpty else { return false }

        if let section = SkyLightCapture.hardwareComposite(of: items.map(\.windowID)),
           let cropped = Self.croppedImages(from: section, for: items) {
            images = cropped
            return true
        }

        guard let section = SkyLightCapture.composite(
            of: items.map(\.windowID), options: [.boundsIgnoreFraming, .bestResolution]
        ),
              let cropped = Self.croppedImages(from: section, for: items)
        else {
            Log.menuBar.error("Standalone bar: the section could not be photographed")
            return false
        }
        images = cropped
        return true
    }

    /// Splits the one image returned for a hardware window list into its status-item stills.
    static func croppedImages(
        from section: CGImage, for items: [MenuBarItem]
    ) -> [UInt32: CGImage]? {
        guard let first = items.first else { return nil }
        let union = items.dropFirst().reduce(first.frame) { $0.union($1.frame) }
        guard union.width > 0 else { return nil }
        // The capture is at backing-store resolution, so its pixels are a scaled copy of the
        // rect it covers. Derived rather than assumed: it is 2x on every display Bouncer has
        // been run on, but the crops go wrong silently if that ever stops being true.
        let scale = CGFloat(section.width) / union.width
        var cropped: [UInt32: CGImage] = [:]
        for item in items {
            let crop = CGRect(
                x: (item.frame.minX - union.minX) * scale,
                y: (item.frame.minY - union.minY) * scale,
                width: item.frame.width * scale,
                height: item.frame.height * scale
            )
            guard let image = section.cropping(to: crop), Self.containsVisiblePixels(image)
            else { return nil }
            cropped[item.windowID] = image
        }
        return cropped.count == items.count ? cropped : nil
    }

    /// Whether a structurally valid capture contains anything WindowServer has actually drawn.
    /// Parked and not-yet-rendered status items can return normal dimensions with zero alpha in
    /// every pixel, which must not be cached as a successful photograph.
    static func containsVisiblePixels(_ image: CGImage) -> Bool {
        guard image.width > 0, image.height > 0 else { return false }
        let bytesPerRow = image.width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * image.height)
        guard let context = CGContext(
            data: &pixels,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                | CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] > 0 }
    }

    /// Drops the pictures. Nothing is running, so there is nothing else to stop.
    public func stop() {
        images.removeAll()
    }
}
