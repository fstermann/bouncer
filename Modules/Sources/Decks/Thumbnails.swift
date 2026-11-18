import AppKit
import ScreenCaptureKit

/// Pictures of windows, taken once each when the overview opens.
///
/// Each is kept at the size a card shows it rather than the window's own, and arrives on its own, so a
/// slow window holds up only its own card.
enum Thumbnails {
    /// The longest side a picture is taken at, in points; a tray card is the largest place one shows.
    static let longestSide: CGFloat = 520

    /// The size a window of `size` is captured at: scaled down to fit `longest` on its longer side,
    /// times the display's scale, never up.
    static func captureSize(of size: CGSize, longest: CGFloat, scale: CGFloat) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        let fit = min(1, longest / max(size.width, size.height))
        return CGSize(width: (size.width * fit * scale).rounded(), height: (size.height * fit * scale).rounded())
    }

    /// Calls `deliver` on the main actor with each window's picture as it arrives, on any Space.
    ///
    /// SkyLight's capture takes every window, full screen apps' among them, in about 20 ms each; it
    /// blocks, so capture runs outside the main actor, front window first. ScreenCaptureKit, which fails on
    /// full screen apps not in front, takes only what SkyLight could not. A window neither takes keeps its icon.
    static func capture(
        _ windows: [CGWindowID], scale: CGFloat,
        imageOf: @Sendable (CGWindowID) -> CGImage? = WindowCapture.image,
        deliver: @escaping @MainActor (CGWindowID, CGImage) -> Void
    ) async {
        var missed: [CGWindowID] = []
        for id in windows {
            guard !Task.isCancelled else { return }
            if let image = imageOf(id) {
                guard !Task.isCancelled else { return }
                await deliver(id, scaled(image, longest: longestSide, scale: 1))
            } else {
                missed.append(id)
            }
        }
        guard !missed.isEmpty, !Task.isCancelled,
              let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        else { return }
        let wanted = Set(missed)
        let requests = content.windows.filter { wanted.contains($0.windowID) }
            .compactMap { request(for: $0, scale: scale) }
        await withTaskGroup(of: Void.self) { group in
            for request in requests {
                group.addTaskUnlessCancelled {
                    guard !Task.isCancelled, let image = try? await SCScreenshotManager.captureImage(
                        contentFilter: request.filter, configuration: request.config
                    ), !Task.isCancelled else { return }
                    await deliver(request.id, image)
                }
            }
        }
    }

    /// `image` drawn at `captureSize`, or itself when it is no larger.
    static func scaled(_ image: CGImage, longest: CGFloat, scale: CGFloat) -> CGImage {
        let size = captureSize(
            of: CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale),
            longest: longest, scale: scale
        )
        guard Int(size.width) < image.width,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
              )
        else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return context.makeImage() ?? image
    }

    /// What one capture needs, built before the captures start: the window it is built from is not
    /// `Sendable`, and the filter and configuration are only read from here on.
    private struct Request: @unchecked Sendable {
        let id: CGWindowID
        let filter: SCContentFilter
        let config: SCStreamConfiguration
    }

    private static func request(for window: SCWindow, scale: CGFloat) -> Request? {
        let size = captureSize(of: window.frame.size, longest: longestSide, scale: scale)
        guard size.width > 0 else { return nil }
        let config = SCStreamConfiguration()
        config.width = Int(size.width)
        config.height = Int(size.height)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        return Request(id: window.windowID, filter: SCContentFilter(desktopIndependentWindow: window), config: config)
    }
}

/// SkyLight's capture of one window, as the window server last drew it, Space or no Space.
///
/// Private and resolved at runtime; `nil` without it. Taken at one pixel per point, half the work of a
/// Retina capture and still larger than a tray card.
enum WindowCapture {
    private typealias Capture = @convention(c) (Int32, UnsafePointer<UInt32>, Int32, UInt32) -> Unmanaged<CFArray>?

    private struct Calls: @unchecked Sendable {
        let connection: Int32
        let capture: Capture
    }

    private static let calls: Calls? = {
        guard let sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let connection = dlsym(sky, "SLSMainConnectionID"),
              let capture = dlsym(sky, "SLSHWCaptureWindowList")
        else { return nil }
        let main = unsafeBitCast(connection, to: (@convention(c) () -> Int32).self)
        return Calls(connection: main(), capture: unsafeBitCast(capture, to: Capture.self))
    }()

    static func image(of window: CGWindowID) -> CGImage? {
        guard let calls else { return nil }
        var id = window
        // 1 << 11: the whole window, covered or not; 1 << 9: one pixel per point.
        let images = calls.capture(calls.connection, &id, 1, 1 << 11 | 1 << 9)?.takeRetainedValue() as? [CGImage]
        return images?.first
    }
}
