import CoreGraphics
import Darwin

/// Photographs status item windows where they are, including off the display.
///
/// ScreenCaptureKit cannot reach a window parked past the edge of a display, and it announces
/// itself: every capture inserts the recording indicator into the menu bar, which pushes every
/// item along. This is the call the public API replaced, resolved at runtime — a macOS release
/// that drops it leaves the bar without pictures rather than crashing.
///
/// It photographs status items, not the bar they sit in: the window server's own menu bar
/// windows come back nil. Nothing needs them — the cover is a flat colour.
enum SkyLightCapture {
    private typealias CreateImageFromArray = @convention(c) (
        CGRect, CFArray, CGWindowImageOption
    ) -> Unmanaged<CGImage>?

    private static let createImage: CreateImageFromArray? = {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW
        ), let symbol = dlsym(handle, "SLWindowListCreateImageFromArray") else { return nil }
        return unsafeBitCast(symbol, to: CreateImageFromArray.self)
    }()

    /// Whether the capture path exists on this system.
    static var isAvailable: Bool { createImage != nil }

    /// Every window in one picture, at the union of their bounds.
    ///
    /// One call rather than one per window: the cost is per call, not per window.
    static func composite(of windowIDs: [UInt32], options: CGWindowImageOption) -> CGImage? {
        guard let createImage else { return nil }
        var pointers: [UnsafeRawPointer?] = windowIDs.compactMap {
            UnsafeRawPointer(bitPattern: UInt($0))
        }
        guard !pointers.isEmpty else { return nil }
        var callbacks = CFArrayCallBacks(
            version: 0, retain: nil, release: nil, copyDescription: nil, equal: nil
        )
        guard let windows = CFArrayCreate(nil, &pointers, pointers.count, &callbacks)
        else { return nil }
        // `.null` asks for the union of the windows' own bounds, which is what makes a parked
        // item come back as its own picture rather than an empty crop of the display.
        return createImage(.null, windows, options)?.takeRetainedValue()
    }
}
