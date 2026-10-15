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

    private typealias MainConnectionID = @convention(c) () -> UInt32
    private typealias CaptureWindowList = @convention(c) (
        UInt32, UnsafePointer<UInt32>, Int32, UInt32
    ) -> Unmanaged<CFArray>?

    private static let mainConnectionID: MainConnectionID? = symbol(named: "SLSMainConnectionID")
    private static let captureWindowList: CaptureWindowList? = symbol(named: "CGSHWCaptureWindowList")

    /// Whether the capture path exists on this system.
    static var isAvailable: Bool { createImage != nil }

    /// Photographs the requested windows from their backing surfaces in one union-sized image.
    /// The older composite call returns the same dimensions but transparent pixels on macOS 26;
    /// this hardware path retains the pixels once WindowServer has drawn the items on-screen.
    static func hardwareComposite(of windowIDs: [UInt32]) -> CGImage? {
        guard let mainConnectionID, let captureWindowList, !windowIDs.isEmpty else { return nil }
        let ids = windowIDs
        let unmanaged = ids.withUnsafeBufferPointer { buffer -> Unmanaged<CFArray>? in
            guard let baseAddress = buffer.baseAddress else { return nil }
            return captureWindowList(mainConnectionID(), baseAddress, Int32(buffer.count), 0)
        }
        guard let unmanaged else { return nil }
        let array = unmanaged.takeRetainedValue()
        guard CFArrayGetCount(array) == 1,
              let pointer = CFArrayGetValueAtIndex(array, 0)
        else { return nil }
        let value = Unmanaged<CFTypeRef>.fromOpaque(pointer).takeUnretainedValue()
        guard CFGetTypeID(value) == CGImage.typeID else { return nil }
        return Unmanaged<CGImage>.fromOpaque(pointer).takeUnretainedValue()
    }

    private static func symbol<T>(named name: String) -> T? {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW
        ), let value = dlsym(handle, name) else { return nil }
        return unsafeBitCast(value, to: T.self)
    }

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
