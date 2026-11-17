import AppKit
import Observation

/// What one opening of the overview shows. Built when it opens and dropped when it closes.
@MainActor
@Observable
final class Overview {
    let windows: [WindowInfo]
    let wallpaper: NSImage?
    let canRaise: Bool
    let canSeeTitles: Bool
    /// Each window's picture, once it has arrived.
    var thumbnails: [CGWindowID: NSImage] = [:]
    @ObservationIgnored private var icons: [pid_t: NSImage] = [:]

    /// The user picked windows to bring forward, the last of them focused.
    @ObservationIgnored var onPick: (@MainActor ([WindowInfo]) -> Void)?
    @ObservationIgnored var onDismiss: (@MainActor () -> Void)?
    /// The user asked for a permission's pane in System Settings.
    @ObservationIgnored var onGrant: (@MainActor (Permission) -> Void)?

    enum Permission {
        case screenRecording, accessibility
    }

    init(windows: [WindowInfo], wallpaper: NSImage?, canRaise: Bool, canSeeTitles: Bool) {
        self.windows = windows
        self.wallpaper = wallpaper
        self.canRaise = canRaise
        self.canSeeTitles = canSeeTitles
    }

    func icon(of window: WindowInfo) -> NSImage {
        if let icon = icons[window.pid] { return icon }
        let icon = NSRunningApplication(processIdentifier: window.pid)?.icon
            ?? NSWorkspace.shared.icon(for: .application)
        icons[window.pid] = icon
        return icon
    }
}
