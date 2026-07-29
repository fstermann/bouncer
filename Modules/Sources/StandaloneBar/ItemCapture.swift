import BouncerFoundation
import Observation
// ScreenCaptureKit's types are only annotated `Sendable` in the macOS 26 SDK. Bouncer builds
// against Xcode 16.4 too, where handing a filter to a framework call that is nonisolated —
// exactly how the API is meant to be used — is an error rather than a warning.
@preconcurrency import ScreenCaptureKit

/// Pictures of the status items the standalone bar replicates.
///
/// One screenshot per item, taken as the bar opens. Not a stream, and that is the whole
/// point: a continuous capture puts the large screen recording pill in the menu bar for as
/// long as it runs, while one-shot captures rate only the small dot beside Control Center.
/// The pill is wide enough to push every item along as it arrives — moving the very items
/// being replicated, and with them the menus that open from them.
///
/// The cost is that a replica is a still. An item that changes while the bar is open — a
/// clock, a badge arriving — keeps the face it had when the bar opened. The bar is opened,
/// used and dismissed, so it holds that face for seconds at a time.
///
/// Items are captured one window at a time because a display-scoped capture does not resolve
/// individual items, and an item parked off the display has no pixels at all — measured, and
/// it comes back empty. That is why the section has to be revealed and covered first.
///
/// Occlusion is irrelevant to a window capture, which is what makes the cover possible: an
/// item under an opaque window still yields its own pixels.
@MainActor
@Observable
public final class ItemCapture {
    /// The picture of each item, keyed by window ID.
    public private(set) var images: [UInt32: CGImage] = [:]

    public init() {}

    /// Captures every item once. About 9 ms each, and taken in turn: ScreenCaptureKit
    /// serialises them anyway, so a task group costs the same and buys nothing.
    ///
    /// The window list is handed in rather than fetched: enumerating it costs about as much
    /// as all the screenshots together, and the caller has already paid for one.
    public func begin(_ items: [MenuBarItem], in content: SCShareableContent) async {
        images.removeAll()
        guard !items.isEmpty else { return }

        let windowsByID = Dictionary(
            content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first }
        )

        for window in items.compactMap({ windowsByID[$0.windowID] }) {
            if let image = await screenshot(window) { images[window.windowID] = image }
        }
    }

    /// Drops the pictures. Nothing is running, so there is nothing else to stop.
    public func stop() {
        images.removeAll()
    }

    private func screenshot(_ window: SCWindow) async -> CGImage? {
        let configuration = SCStreamConfiguration()
        // Backing-store resolution, so a replica drawn at point size stays sharp.
        configuration.width = Int(window.frame.width * 2)
        configuration.height = Int(window.frame.height * 2)
        configuration.showsCursor = false
        configuration.captureResolution = .best
        // A status item is an icon on nothing. Composited onto the default background it
        // becomes an opaque tile, which is not what sits in a menu bar.
        configuration.backgroundColor = .clear

        return try? await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: window),
            configuration: configuration
        )
    }
}
