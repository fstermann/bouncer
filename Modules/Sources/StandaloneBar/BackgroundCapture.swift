import BouncerFoundation
import ScreenCaptureKit

/// A picture of the menu bar as it looks with the replicated items removed.
///
/// This is what the cover is painted with. The items are not moved off the display — they
/// stay where they are so they keep producing pixels — so something has to hide them, and
/// the only cover indistinguishable from the real bar is the real bar itself. Every material
/// AppKit offers reads as a patch stuck on top, because the menu bar is translucent over
/// whatever is behind it.
///
/// Taken once per open rather than streamed. A stream would keep the cover in step with the
/// shadows that shift under the bar as windows move, but it also earns the large screen
/// recording pill, which lands *in* the bar and pushes every item along. A still cover can
/// drift; a moving bar breaks the replicas' alignment with the items whose menus they open.
///
/// Bouncer's own cover is excluded along with the items. It sits over this very strip, so
/// leaving it in feeds the picture back into itself.
public enum BackgroundCapture {
    /// One capture of `rect` with `windowIDs` left out.
    ///
    /// A window list may be handed in when the caller already holds one; the fetch is the
    /// expensive half of this. It has to be fresh enough to contain everything being excluded
    /// — a window created since it was taken is not in it, and so is not left out.
    public static func sample(
        rect: CGRect, excluding windowIDs: Set<UInt32>, in shared: SCShareableContent? = nil
    ) async -> CGImage? {
        var fetched = shared
        if fetched == nil {
            fetched = try? await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false
            )
        }
        guard let content = fetched, let display = content.displays.first else {
            Log.menuBar.error("Standalone bar: no display to capture the bar from")
            return nil
        }

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = rect
        configuration.width = Int(rect.width * 2)
        configuration.height = Int(rect.height * 2)
        configuration.showsCursor = false
        configuration.captureResolution = .best

        // Excluding the item windows renders the strip as empty menu bar — background,
        // shadows and all — which is exactly what belongs under the replicas.
        return try? await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(
                display: display,
                excludingWindows: content.windows.filter { windowIDs.contains($0.windowID) }
            ),
            configuration: configuration
        )
    }
}
