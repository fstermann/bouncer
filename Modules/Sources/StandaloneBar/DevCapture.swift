#if DEV
import AppKit
import ScreenCaptureKit

/// A recording of the top of the main display around an action, marked where the action was taken:
/// what `make bench` times opens and closes by.
///
/// A movie's times start at its first frame, on no clock the action can be read on, so a square in the
/// bottom right corner of the recorded area turns from black to white as the action is posted. Recorded
/// to a file because a stream handing frames to the app puts the system's sharing item in the menu bar,
/// which moves every item it is meant to time. The pointer is left out, so its moves are no change.
@MainActor
enum DevCapture {
    /// Long enough for the recording's first frames, which come late and black, to be over.
    static let warmUp: Duration = .seconds(1)
    /// The marker's side, in points.
    static let markerSize: CGFloat = 16

    static func capture(
        seconds: Double, height: CGFloat, scale: CGFloat, to url: URL, action: () async -> String
    ) async throws -> String {
        guard #available(macOS 15, *) else { throw DevCamera.Failure.needsMacOS15 }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }),
              let screen = NSScreen.main
        else { throw DevCamera.Failure.noDisplay }
        let marker = Self.marker(on: screen, height: height)
        defer { marker.orderOut(nil) }
        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(x: 0, y: 0, width: screen.frame.width, height: height)
        config.width = Int(screen.frame.width * scale)
        config.height = Int(height * scale)
        config.showsCursor = false
        config.minimumFrameInterval = CMTime(value: 1, timescale: 120)
        try? FileManager.default.removeItem(at: url)
        let output = SCRecordingOutputConfiguration()
        output.outputURL = url
        output.outputFileType = .mov
        let end = RecordingEnd()
        let recording = SCRecordingOutput(configuration: output, delegate: end)
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addRecordingOutput(recording)
        try await stream.startCapture()
        try await Task.sleep(for: warmUp)
        marker.contentView?.layer?.backgroundColor = NSColor.white.cgColor
        let reply = await action()
        try await Task.sleep(for: .seconds(seconds))
        try await stream.stopCapture()
        await end.finished()
        if let error = end.error { throw error }
        return "\(url.path) \(reply)"
    }

    /// A black square in the bottom right corner of the recorded area, above everything.
    private static func marker(on screen: NSScreen, height: CGFloat) -> NSWindow {
        let frame = CGRect(
            x: screen.frame.maxX - markerSize, y: screen.frame.maxY - height,
            width: markerSize, height: markerSize
        )
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .screenSaver
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.black.cgColor
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.orderFrontRegardless()
        return window
    }
}
#endif
