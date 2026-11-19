import AppKit
import ApplicationServices

/// Adds and removes desktops by opening Mission Control and using the Dock's Accessibility elements for
/// its Spaces bar, as Hammerspoon's `hs.spaces` does.
///
/// No call adds or removes a desktop while System Integrity Protection is on; the bar's elements exist
/// only while Mission Control is open, so it shows for a moment each time. Needs Accessibility.
enum MissionControl {
    /// Adds a desktop after the last one of the display `display`. Returns whether the Dock took it.
    static func addDesktop(on display: CGDirectDisplayID) async -> Bool {
        await withSpacesBar(on: display, retrying: false) { spaces in
            guard let add = child(of: spaces, identifier: "mc.spaces.add") else { return false }
            return AXUIElementPerformAction(add, kAXPressAction as CFString) == .success
        }
    }

    /// Removes the Space at `index` among every Space of the display `display`, full screen ones counted,
    /// once the bar lists `count` of them. Its windows move to another desktop.
    static func removeDesktop(at index: Int, of count: Int, on display: CGDirectDisplayID) async -> Bool {
        await withSpacesBar(on: display, retrying: true) { spaces in
            // A bar listing another number of Spaces than SkyLight did could remove the wrong one.
            guard let list = child(of: spaces, identifier: "mc.spaces.list"),
                  let entries = children(of: list), entries.count == count, entries.indices.contains(index)
            else { return false }
            return AXUIElementPerformAction(entries[index], "AXRemoveDesktop" as CFString) == .success
        }
    }

    /// Opens Mission Control, runs `body` on the display's Spaces bar, and returns once it has closed.
    /// With `retrying`, `body` runs again until it succeeds: the bar's entries answer only once Mission
    /// Control has finished opening.
    private static func withSpacesBar(
        on display: CGDirectDisplayID, retrying: Bool, _ body: (AXUIElement) -> Bool
    ) async -> Bool {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return false }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        if group(in: app) == nil { toggle() }
        var done = false
        if let spaces = await spacesBar(of: app, display: display) {
            for _ in 0..<(retrying ? 20 : 1) {
                done = body(spaces)
                if done { break }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        if group(in: app) != nil { toggle() }
        for _ in 0..<40 where group(in: app) != nil {
            try? await Task.sleep(for: .milliseconds(25))
        }
        return done
    }

    private static func spacesBar(of app: AXUIElement, display: CGDirectDisplayID) async -> AXUIElement? {
        for _ in 0..<80 {
            if let found = group(in: app).flatMap({ spacesBar(in: $0, display: display) }) { return found }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return nil
    }

    /// The Dock's Mission Control group, present only while Mission Control is open.
    private static func group(in dock: AXUIElement) -> AXUIElement? {
        child(of: dock, identifier: "mc")
    }

    private static func spacesBar(in group: AXUIElement, display: CGDirectDisplayID) -> AXUIElement? {
        let displays = (children(of: group) ?? []).filter { identifier(of: $0) == "mc.display" }
        let own = displays.first { displayID(of: $0) == display } ?? (displays.count == 1 ? displays.first : nil)
        return own.flatMap { child(of: $0, identifier: "mc.spaces") }
    }

    private static func child(of element: AXUIElement, identifier wanted: String) -> AXUIElement? {
        children(of: element)?.first { identifier(of: $0) == wanted }
    }

    private static func children(of element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? [AXUIElement]
    }

    private static func identifier(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &value)
        return value as? String
    }

    private static func displayID(of element: AXUIElement) -> CGDirectDisplayID? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, "AXDisplayID" as CFString, &value)
        return (value as? NSNumber)?.uint32Value
    }

    private typealias SendNotification = @convention(c) (CFString, Int32) -> Int32

    /// Opens or closes Mission Control, as its key does, through the Dock's private notification.
    private static func toggle() {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CoreDockSendNotification") else { return }
        _ = unsafeBitCast(symbol, to: SendNotification.self)("com.apple.expose.awake" as CFString, 0)
    }
}
