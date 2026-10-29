#if DEBUG
import AppKit
import ScreenCaptureKit

/// Pictures and recordings of the top of the main display, as a person sees it: the bar, its
/// background, Bouncer's windows and the pointer. Bounded: a recording stops itself.
@MainActor
enum DebugCamera {
    /// The bar plus room for the panel below it.
    static let defaultHeight: CGFloat = 120
    static let longestRecording: Double = 30

    enum Failure: LocalizedError {
        case noDisplay, unencodable, needsMacOS15

        var errorDescription: String? {
            switch self {
            case .noDisplay: "no main display to capture"
            case .unencodable: "the picture would not encode"
            case .needsMacOS15: "recording needs macOS 15"
            }
        }
    }

    static func shoot(height: CGFloat, to url: URL) async throws -> String {
        let (filter, config) = try await setUp(height: height)
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw Failure.unencodable
        }
        try data.write(to: url)
        return url.path
    }

    static func record(seconds: Double, height: CGFloat, to url: URL) async throws -> String {
        guard #available(macOS 15, *) else { throw Failure.needsMacOS15 }
        let (filter, config) = try await setUp(height: height)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        try? FileManager.default.removeItem(at: url)
        let output = SCRecordingOutputConfiguration()
        output.outputURL = url
        output.outputFileType = .mov
        let end = RecordingEnd()
        let recording = SCRecordingOutput(configuration: output, delegate: end)
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addRecordingOutput(recording)
        try await stream.startCapture()
        try await Task.sleep(for: .seconds(seconds))
        try await stream.stopCapture()
        await end.finished()
        if let error = end.error { throw error }
        return url.path
    }

    private static func setUp(height: CGFloat) async throws -> (SCContentFilter, SCStreamConfiguration) {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }),
              let screen = NSScreen.main
        else { throw Failure.noDisplay }
        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(x: 0, y: 0, width: screen.frame.width, height: height)
        config.width = Int(screen.frame.width * screen.backingScaleFactor)
        config.height = Int(height * screen.backingScaleFactor)
        config.showsCursor = true
        return (SCContentFilter(display: display, excludingWindows: []), config)
    }
}

/// Waits for a recording's file to be finished, which comes after the stream stops.
@available(macOS 15, *)
private final class RecordingEnd: NSObject, SCRecordingOutputDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var finish: CheckedContinuation<Void, Never>?
    private var isDone = false
    private(set) var error: Error?

    func finished() async {
        await withCheckedContinuation { continuation in
            lock.withLock {
                if isDone { continuation.resume() } else { finish = continuation }
            }
        }
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        resume()
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        lock.withLock { self.error = error }
        resume()
    }

    private func resume() {
        lock.withLock {
            isDone = true
            finish?.resume()
            finish = nil
        }
    }
}
#endif
