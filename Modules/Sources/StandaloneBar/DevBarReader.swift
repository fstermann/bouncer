#if DEV
import AppKit

/// What `DevHarness` reads the bar with.
enum DevBarReader {
    struct OwnWindow {
        let id: UInt32
        let layer: Int
        let frame: CGRect
    }

    /// Every visible status item by owning app, Bouncer's included.
    static func accessibilityItems() async -> [(owner: String, frame: CGRect)] {
        let apps = await MainActor.run {
            NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0.localizedName ?? "?") }
        }
        let found = await withTaskGroup(of: [(owner: String, frame: CGRect)].self) { group in
            for (pid, name) in apps {
                group.addTask { ClickForwarder.statusItems(of: pid).map { (name, $0.frame) } }
            }
            var all: [(owner: String, frame: CGRect)] = []
            for await items in group { all.append(contentsOf: items) }
            return all
        }
        return found.sorted { $0.frame.minX < $1.frame.minX }
    }

    /// Bouncer's own windows near the top of the screen, in window-server coordinates.
    static func bouncerWindows() -> [OwnWindow] {
        let pid = ProcessInfo.processInfo.processIdentifier
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return [] }
        return list.compactMap { window in
            guard window[kCGWindowOwnerPID as String] as? Int32 == pid,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let id = window[kCGWindowNumber as String] as? UInt32,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  rect.width > 1, rect.minY < 200
            else { return nil }
            return OwnWindow(id: id, layer: layer, frame: rect)
        }
        .sorted { $0.layer < $1.layer }
    }
}
#endif
