import BouncerFoundation
import Observation
import ScreenCaptureKit
import VideoToolbox

/// Live images of the status items the standalone bar replicates.
///
/// One stream per item, running only while the bar is open. That shape is forced by what
/// the window server will give us: a display-scoped capture does not resolve individual
/// items, and an item parked off the display has no pixels at all — so the items are left
/// where they are, covered, and captured one window at a time.
///
/// Occlusion is irrelevant to a window capture, which is what makes the cover possible: an
/// item under an opaque window still yields its own pixels.
@MainActor
@Observable
public final class ItemCapture {
    /// The most recent frame for each item, keyed by window ID.
    public private(set) var images: [UInt32: CGImage] = [:]

    private var streams: [UInt32: SCStream] = [:]
    private var warmUp: Task<Void, Never>?

    public init() {}

    /// Captures every item once, then brings the live streams up behind that.
    ///
    /// Returns as soon as `images` is populated — about 57 ms for a section of seven — so
    /// the bar can be drawn immediately. Streams are started one at a time afterwards and
    /// cost roughly half a second in total, during which each item shows its open-time
    /// image until its own stream takes over.
    ///
    /// The two phases are deliberately not separate calls. Waiting on the streams before
    /// drawing would turn a 57 ms open into a 500 ms one, and that is too easy to do by
    /// accident from the outside.
    ///
    /// (Starting the streams concurrently was the intent and would shorten the tail, but
    /// ScreenCaptureKit's types are not `Sendable`, and every shape that carries them
    /// through a task group either trips the isolation checker or needs unchecked escapes
    /// in the hot path. The saving has not been measured.)
    public func begin(_ items: [MenuBarItem]) async {
        await stop()
        guard !items.isEmpty else { return }

        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false
        ) else {
            Log.menuBar.error("Standalone bar: no shareable content; is Screen Recording granted?")
            return
        }
        let windowsByID = Dictionary(
            content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first }
        )
        let windows = items.compactMap { windowsByID[$0.windowID] }

        for window in windows {
            if let image = await screenshot(window) { images[window.windowID] = image }
        }

        warmUp = Task { @MainActor [weak self] in
            for window in windows {
                guard let self, !Task.isCancelled else { return }
                self.streams[window.windowID] = await self.startStream(for: window)
            }
            Log.menuBar.debug(
                "Standalone bar: \(self?.streams.count ?? 0, privacy: .public) item streams live")
        }
    }

    /// Tears everything down. Nothing may keep running once the bar is closed.
    public func stop() async {
        warmUp?.cancel()
        warmUp = nil
        let running = streams.values
        streams.removeAll()
        images.removeAll()
        for stream in running { try? await stream.stopCapture() }
    }

    /// One frame, now. Costs about 9 ms per item — cheap enough to open on, too slow to
    /// track a clock with, which is what the streams are for.
    private func screenshot(_ window: SCWindow) async -> CGImage? {
        let configuration = SCStreamConfiguration()
        configuration.width = Int(window.frame.width * 2)
        configuration.height = Int(window.frame.height * 2)
        configuration.showsCursor = false
        configuration.captureResolution = .best
        return try? await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: window),
            configuration: configuration
        )
    }

    private func startStream(for window: SCWindow) async -> SCStream? {
        let configuration = SCStreamConfiguration()
        // Backing-store resolution, so a replica drawn at point size stays sharp.
        configuration.width = Int(window.frame.width * 2)
        configuration.height = Int(window.frame.height * 2)
        configuration.showsCursor = false
        configuration.captureResolution = .best
        configuration.queueDepth = 3

        let stream = SCStream(
            filter: SCContentFilter(desktopIndependentWindow: window),
            configuration: configuration,
            delegate: nil
        )
        let windowID = window.windowID
        let receiver = FrameReceiver { [weak self] image in
            Task { @MainActor in self?.images[windowID] = image }
        }

        do {
            try stream.addStreamOutput(
                receiver,
                type: .screen,
                sampleHandlerQueue: DispatchQueue(label: "com.bouncer.capture.item.\(windowID)")
            )
            try await stream.startCapture()
        } catch {
            Log.menuBar.error("Standalone bar: item stream failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        // The receiver has to outlive this scope; the stream does not retain it.
        objc_setAssociatedObject(stream, "receiver", receiver, .OBJC_ASSOCIATION_RETAIN)
        return stream
    }
}

/// Turns stream callbacks into images.
///
/// Frames arrive on the stream's own queue, so this deliberately owns no state beyond the
/// handler it forwards to.
final class FrameReceiver: NSObject, SCStreamOutput, @unchecked Sendable {
    private let onFrame: @Sendable (CGImage) -> Void

    init(onFrame: @escaping @Sendable (CGImage) -> Void) {
        self.onFrame = onFrame
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let pixelBuffer = CMSampleBufferGetImageBuffer(buffer)
        else { return }

        var image: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &image)
        if let image { onFrame(image) }
    }
}
