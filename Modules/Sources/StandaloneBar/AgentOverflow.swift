import AppKit

/// The chevron macOS 27 shows when status items do not fit right of the notch.
///
/// Opened, it draws the overflowed items left of the notch, over the app menus, sliding them out
/// of the notch itself. It stays open across a collapse and a reveal, so whoever opens it has to
/// close it. Only the one in `MenuBarAgent`'s own item list is live: its full tree also holds
/// stale copies, whose press flips the label and draws nothing. Measured in SPIKES.md.
enum AgentOverflow {
    enum State: Equatable {
        case absent, closed, open
    }

    static var state: State {
        guard let chevron = chevron() else { return .absent }
        return identifier(of: chevron)?.hasSuffix(expandedSuffix) == true ? .open : .closed
    }

    /// Opens the overflow if there is one to open. Whether it did shows in `state`.
    static func open() {
        guard let chevron = chevron(), state == .closed else { return }
        AXUIElementPerformAction(chevron, kAXPressAction as CFString)
    }

    static func close() {
        guard let chevron = chevron(), state == .open else { return }
        AXUIElementPerformAction(chevron, kAXPressAction as CFString)
    }

    /// Where the chevron sits in the bar, `nil` when it is not there.
    static var frame: CGRect? {
        chevron().flatMap(ClickForwarder.itemFrame(of:))
    }

    /// Waits for the chevron after the bar was given more than fits. A bounded poll: nothing says
    /// when `MenuBarAgent` has laid the bar out again.
    static func appearance() async {
        for _ in 0..<attemptLimit where state == .absent {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private static let attemptLimit = 30

    private static func chevron() -> AXUIElement? {
        guard let agent = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.MenuBarAgent"
        }) else { return nil }
        return ClickForwarder.statusItems(of: agent.processIdentifier)
            .map(\.element.element)
            .first { identifier(of: $0)?.hasPrefix(chevronIdentifier) == true }
    }

    private static func identifier(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &value)
        return value as? String
    }

    private static let chevronIdentifier = "menu-bar-overflow-indicator"
    private static let expandedSuffix = "-expanded"
}
