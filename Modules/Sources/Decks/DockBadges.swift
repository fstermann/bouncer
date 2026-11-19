import AppKit

/// The badges apps show on their Dock icons, such as an unread count, read from the Dock through
/// Accessibility.
enum DockBadges {
    /// Each running app's badge text, by process. Blocks on the Dock's replies, so never on the main actor.
    static func read() -> [pid_t: String] {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return [:] }
        let apps = NSWorkspace.shared.runningApplications
        let byPath = Dictionary(
            apps.compactMap { app in app.bundleURL.map { ($0.standardized.path, app.processIdentifier) } }
        ) { first, _ in first }
        var badges: [pid_t: String] = [:]
        for item in children(of: AXUIElementCreateApplication(dock.processIdentifier)).flatMap(children(of:)) {
            guard let label = value(item, "AXStatusLabel") as? String, !label.isEmpty,
                  let url = value(item, kAXURLAttribute) as? URL,
                  let pid = byPath[url.standardized.path]
            else { continue }
            badges[pid] = label
        }
        return badges
    }

    /// One badge for several apps' badges: the sum of their counts, or a dot when none is a count.
    static func combined(_ labels: [String]) -> String? {
        guard !labels.isEmpty else { return nil }
        let total = labels.compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.reduce(0, +)
        return total > 0 ? String(total) : "•"
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }
}
