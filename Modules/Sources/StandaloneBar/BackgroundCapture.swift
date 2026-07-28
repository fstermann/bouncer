import BouncerFoundation
import Observation
import ScreenCaptureKit
import VideoToolbox

/// A live image of the menu bar as it would look with the replicated items removed.
///
/// This is what the cover is painted with. The items are not moved off the display — they
/// stay where they are so they keep producing pixels — so something has to hide them, and
/// the only cover indistinguishable from the real bar is the real bar itself. Every
/// material AppKit offers reads as a patch stuck on top, because the menu bar is
/// translucent over whatever is behind it.
///
/// It has to be a stream rather than one sample taken on open. Window shadows stack under
/// the menu bar and shift whenever any window moves, and a cover sampled once drifts badly
/// once that happens — far past the point of being noticeable.
@MainActor
@Observable
public final class BackgroundCapture {
    /// The menu bar strip with the items excluded, or `nil` before the first frame.
    public private(set) var image: CGImage?

    private var stream: SCStream?

    public init() {}

    /// One capture of the strip without the items, for putting the cover up immediately.
    ///
    /// Starting the stream takes long enough that the freshly revealed items would be
    /// visible while waiting for its first frame. This costs about 11 ms, so the cover can
    /// be up within a frame and the stream can take over behind it.
    public static func sample(rect: CGRect, excluding items: [MenuBarItem]) async -> CGImage? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false
        ), let display = content.displays.first else { return nil }

        let excludedIDs = Set(items.map(\.windowID))
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = rect
        configuration.width = Int(rect.width * 2)
        configuration.height = Int(rect.height * 2)
        configuration.showsCursor = false
        configuration.captureResolution = .best

        return try? await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(
                display: display,
                excludingWindows: content.windows.filter { excludedIDs.contains($0.windowID) }
            ),
            configuration: configuration
        )
    }

    /// Starts tracking the strip `rect`, rendering it without `items`.
    public func start(rect: CGRect, excluding items: [MenuBarItem]) async {
        await stop()
        guard rect.width > 0, rect.height > 0 else { return }

        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false
        ), let display = content.displays.first else {
            Log.menuBar.error("Standalone bar: no display for the cover")
            return
        }

        let excludedIDs = Set(items.map(\.windowID))
        let excluded = content.windows.filter { excludedIDs.contains($0.windowID) }

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = rect
        configuration.width = Int(rect.width * 2)
        configuration.height = Int(rect.height * 2)
        configuration.showsCursor = false
        configuration.captureResolution = .best
        configuration.queueDepth = 3

        // Excluding the item windows renders the strip as empty menu bar — background,
        // shadows and all — which is exactly what belongs under the replicas.
        let newStream = SCStream(
            filter: SCContentFilter(display: display, excludingWindows: excluded),
            configuration: configuration,
            delegate: nil
        )
        let receiver = FrameReceiver { [weak self] image in
            Task { @MainActor in self?.image = image }
        }

        do {
            try newStream.addStreamOutput(
                receiver,
                type: .screen,
                sampleHandlerQueue: DispatchQueue(label: "com.bouncer.capture.background")
            )
            try await newStream.startCapture()
        } catch {
            Log.menuBar.error(
                "Standalone bar: cover stream failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        objc_setAssociatedObject(newStream, "receiver", receiver, .OBJC_ASSOCIATION_RETAIN)
        stream = newStream
    }

    public func stop() async {
        let running = stream
        stream = nil
        image = nil
        try? await running?.stopCapture()
    }
}
