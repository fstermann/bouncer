import AppKit
import BouncerFoundation

/// What a screenshot takes in.
public enum ScreenshotArea: Sendable {
    /// The whole display the note is on.
    case screen
    /// A part the user drags out, or a window after Space, the way ⌘⇧4 picks.
    case region
}

/// Screenshots taken by the system's `screencapture`, which is why they need Screen Recording: run by
/// Bouncer, it sees only the wallpaper and Bouncer's own windows without it.
public enum Screenshot {
    /// The picture as PNG; `nil` once the user cancels a region with Escape, or it fails.
    @MainActor public static func take(_ area: ScreenshotArea, of screen: NSScreen?) async -> Data? {
        let file = FileManager.default.temporaryDirectory.appending(path: "Bouncer screenshot \(UUID()).png")
        defer { try? FileManager.default.removeItem(at: file) }
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let rect = screen.map { captureRect(of: $0.frame, mainHeight: mainHeight) }
        let process = Process()
        process.executableURL = URL(filePath: "/usr/sbin/screencapture")
        process.arguments = arguments(for: area, in: rect, to: file.path)
        do {
            try await run(process)
        } catch {
            Log.app.error("screencapture did not start: \(error, privacy: .public)")
            return nil
        }
        return try? Data(contentsOf: file)
    }

    /// Silent, as it is taken in a meeting.
    static func arguments(for area: ScreenshotArea, in rect: CGRect?, to path: String) -> [String] {
        switch area {
        case .region:
            return ["-x", "-i", path]
        case .screen:
            guard let rect else { return ["-x", "-m", path] }
            let bounds = [rect.minX, rect.minY, rect.width, rect.height].map { String(Int($0.rounded())) }
            return ["-x", "-R", bounds.joined(separator: ","), path]
        }
    }

    /// A display's frame in AppKit screen coordinates as `screencapture -R` takes it: from the top
    /// left of the main display, y downwards.
    static func captureRect(of frame: CGRect, mainHeight: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: mainHeight - frame.maxY, width: frame.width, height: frame.height)
    }

    public static var isPermitted: Bool { CGPreflightScreenCaptureAccess() }

    /// Prompts once; after that macOS only opens System Settings. A grant counts from the next launch.
    public static func requestPermission() {
        CGRequestScreenCaptureAccess()
    }

    private static func run(_ process: Process) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { _ in continuation.resume() }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}
