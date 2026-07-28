import AppKit
import ApplicationServices

/// Opens the real status item behind a replica.
///
/// Accessibility rather than a synthesised click, and that is forced rather than chosen.
/// Since macOS 26 every status item window belongs to Control Center, so a click posted at
/// an item's position reaches only the handful of items Control Center genuinely owns — the
/// clock, Wi-Fi, the battery — and every app's item ignores it, wherever it sits and however
/// the event is addressed.
///
/// Each app still publishes its own items under its extras menu bar, where pressing one
/// opens the same menu a real click would. Position never enters into it, which is also why
/// this survives the cover, the notch and full screen spaces.
///
/// It needs Accessibility. Without it there are no elements to find at all, which is why
/// `isPermitted` exists: the failure is otherwise invisible and reads to the user as a
/// replica that simply does nothing.
/// One item's accessibility element, held for as long as the bar shows that item.
public struct ItemElement: @unchecked Sendable {
    fileprivate let element: AXUIElement
}

public enum ClickForwarder {
    /// Whether other apps' items can be reached at all.
    public static var isPermitted: Bool { AXIsProcessTrusted() }

    /// Asks for Accessibility, showing the system prompt.
    ///
    /// Only ever call this in response to the user turning click forwarding on. Bouncer
    /// asks for no permissions by default, and this is the second one.
    @discardableResult
    public static func requestPermission() -> Bool {
        // The constant is exported as a mutable global, which Swift 6 will not read across
        // isolation; its value is fixed and documented.
        let options = ["AXTrustedCheckOptionPrompt": true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Finds the element behind each of `windowIDs`.
    ///
    /// Worth doing for the whole bar at once, while it opens: every running app has to be
    /// asked for its items and accessibility calls block, so paying that per click puts the
    /// whole sweep in front of the menu — and the apps behind a hidden section tend to sit
    /// late in the list.
    ///
    /// Frames are read here rather than taken from the caller. The menu bar is still
    /// settling when the bar opens, and an item matched against where it was a moment ago
    /// matches nothing.
    ///
    /// Items are matched to elements horizontally: an element is a couple of points shorter
    /// than the window it is drawn in, so their vertical extents never quite line up. It is
    /// position or nothing — the tree knows no window identifiers, and every item's window
    /// names Control Center as its owner.
    ///
    /// Accessibility calls block, so this is never called from the main actor.
    public static func elements(for windowIDs: [UInt32]) async -> [UInt32: ItemElement] {
        let wanted = Set(windowIDs)
        var unmatched = StatusItemScanner.scan().filter { wanted.contains($0.windowID) }
        guard !unmatched.isEmpty else { return [:] }

        let pids = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy != .prohibited }
            .map(\.processIdentifier)

        // One task per app. A couple of processes never answer at all, and asking them in
        // turn spends the whole timeout on each — seconds, all of it in front of a click.
        let candidates = await withTaskGroup(of: [(frame: CGRect, element: ItemElement)].self) { group in
            for pid in pids {
                group.addTask { statusItems(of: pid) }
            }
            var all: [(frame: CGRect, element: ItemElement)] = []
            for await found in group { all.append(contentsOf: found) }
            return all
        }

        var found: [UInt32: ItemElement] = [:]
        for candidate in candidates {
            guard let index = unmatched.firstIndex(where: {
                $0.frame.minX...$0.frame.maxX ~= candidate.frame.midX
            }) else { continue }
            found[unmatched[index].windowID] = candidate.element
            unmatched.remove(at: index)
        }
        return found
    }

    /// Opens the item, as clicking it in the menu bar would.
    ///
    /// The result is deliberately ignored: items that open perfectly well still report the
    /// press as failed, so there is nothing here worth acting on.
    public static func press(_ item: ItemElement) {
        AXUIElementPerformAction(item.element, kAXPressAction as CFString)
    }

    /// The process an item belongs to, for watching what its press opens.
    public static func owner(of item: ItemElement) -> pid_t? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(item.element, &pid) == .success else { return nil }
        return pid
    }

    /// Every status item one app publishes, with where it sits.
    private static func statusItems(of pid: pid_t) -> [(frame: CGRect, element: ItemElement)] {
        let app = AXUIElementCreateApplication(pid)
        // An app that has stopped answering must not hold its own task up for long. A second
        // is generous: the apps that do answer take tens of milliseconds.
        AXUIElementSetMessagingTimeout(app, 1)
        guard let extras = attribute(of: app, named: kAXExtrasMenuBarAttribute),
              let children = attribute(of: extras as! AXUIElement, named: kAXChildrenAttribute)
              as? [AXUIElement]
        else { return [] }

        return children.compactMap { child in
            guard let frame = itemFrame(of: child) else { return nil }
            return (frame, ItemElement(element: child))
        }
    }

    private static func attribute(of element: AXUIElement, named name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    /// Built from position and size rather than read whole: `AXFrame` is not part of the
    /// published attribute set, and these two are.
    private static func itemFrame(of element: AXUIElement) -> CGRect? {
        guard let positionValue = attribute(of: element, named: kAXPositionAttribute),
              let sizeValue = attribute(of: element, named: kAXSizeAttribute)
        else { return nil }

        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }
}
