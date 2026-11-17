import AppKit

/// One app window as the window server lists it.
public struct WindowInfo: Hashable, Sendable, Identifiable {
    /// The window server's number, stable only while the window stays open.
    public let id: CGWindowID
    public let pid: pid_t
    public let bundleID: String?
    public let appName: String
    /// `nil` without Screen Recording: the window server withholds other apps' titles.
    public let title: String?
    /// In the window server's coordinates: from the top left of the main display, y downwards.
    public let frame: CGRect

    public init(id: CGWindowID, pid: pid_t, bundleID: String?, appName: String, title: String?, frame: CGRect) {
        self.id = id
        self.pid = pid
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.frame = frame
    }

    /// The title, or the app's name for a window with none.
    public var label: String {
        guard let title, !title.isEmpty else { return appName }
        return title
    }
}

public enum WindowList {
    /// Smaller than this in either direction is a palette, a tooltip or an invisible helper window.
    static let smallestSide: CGFloat = 60

    /// The ordinary windows in `entries`, front to back as the window server lists them.
    ///
    /// Ordinary means layer 0, drawn, big enough to be a window, and not Bouncer's own.
    static func windows(
        in entries: [[String: Any]], excluding ownPID: pid_t, bundleID: (pid_t) -> String?
    ) -> [WindowInfo] {
        entries.compactMap { entry in
            guard entry[kCGWindowLayer as String] as? Int == 0,
                  let id = entry[kCGWindowNumber as String] as? Int,
                  let pid = entry[kCGWindowOwnerPID as String] as? Int, pid_t(pid) != ownPID,
                  (entry[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  frame.width >= smallestSide, frame.height >= smallestSide
            else { return nil }
            let appName = entry[kCGWindowOwnerName as String] as? String ?? ""
            return WindowInfo(
                id: CGWindowID(id), pid: pid_t(pid), bundleID: bundleID(pid_t(pid)), appName: appName,
                title: entry[kCGWindowName as String] as? String, frame: frame
            )
        }
    }

    /// Every ordinary window on screen now, front to back. Minimized windows and those on other
    /// Spaces are not on screen, so the window server leaves them out.
    @MainActor public static func onScreen() -> [WindowInfo] {
        let entries = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] ?? []
        return windows(in: entries, excluding: ProcessInfo.processInfo.processIdentifier) {
            NSRunningApplication(processIdentifier: $0)?.bundleIdentifier
        }
    }
}
