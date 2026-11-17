import AppKit
import ScreenCaptureKit

/// Pictures of windows, taken once each when the overview opens.
///
/// One capture per window, all at once, each at the size a card shows it rather than the window's own:
/// a full-size picture of every window is most of the wait. Each arrives on its own, so a slow window
/// holds up only its own card.
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

    /// Calls `deliver` on the main actor with each window's picture as it arrives. Windows that cannot
    /// be captured, as those on another Space, are skipped and keep their icon.
    static func capture(
        _ windows: [CGWindowID], scale: CGFloat, deliver: @escaping @MainActor (CGWindowID, CGImage) -> Void
    ) async {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            true, onScreenWindowsOnly: true
        ) else { return }
        let wanted = Set(windows)
        let requests = content.windows.filter { wanted.contains($0.windowID) }
            .compactMap { request(for: $0, scale: scale) }
        await withTaskGroup(of: Void.self) { group in
            for request in requests {
                group.addTask {
                    guard let image = try? await SCScreenshotManager.captureImage(
                        contentFilter: request.filter, configuration: request.config
                    ) else { return }
                    await deliver(request.id, image)
                }
            }
        }
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
