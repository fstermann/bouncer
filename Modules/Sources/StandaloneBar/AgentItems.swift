import AppKit
import BouncerFoundation

/// Status items on macOS 27, where `MenuBarAgent` draws every one of them in a single window and
/// the window list has nothing left to tell them apart by.
///
/// Each app still publishes its visible items through Accessibility. A hidden item drops out of
/// that list and comes back as the same element once revealed, so the element is the item's
/// identity, and an ID made from it lets the rest of the bar go on keying items by number.
/// Measured in SPIKES.md.
enum AgentItems {
    typealias Found = (item: MenuBarItem, element: ItemElement)

    /// Every visible status item but Bouncer's own, drawn `height` tall in the bar.
    static func scan(height: CGFloat) async -> [Found] {
        let own = getpid()
        let pids = await MainActor.run {
            NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy != .prohibited && $0.processIdentifier != own }
                .map(\.processIdentifier)
        }
        // One task per app, as `ClickForwarder` does: an app that has stopped answering must not
        // hold up the ones that do.
        let found = await withTaskGroup(of: [(frame: CGRect, element: ItemElement)].self) { group in
            for pid in pids {
                group.addTask { ClickForwarder.statusItems(of: pid) }
            }
            var all: [(frame: CGRect, element: ItemElement)] = []
            for await items in group { all.append(contentsOf: items) }
            return all
        }
        return found
            .map { found in
                let frame = CGRect(x: found.frame.minX, y: 0, width: found.frame.width, height: height)
                return (MenuBarItem(windowID: id(of: found.element), frame: frame), found.element)
            }
            .sorted { $0.item.frame.minX < $1.item.frame.minX }
    }

    /// The items that came back into `reach` once the section was revealed.
    ///
    /// A bounded poll, like `PlacementWait`: Accessibility says nothing when an item lands. They
    /// were measured landing at once, 34 ms after the reveal, so two equal readings in a row are
    /// taken as the section having arrived.
    static func revealed(in reach: ClosedRange<CGFloat>, height: CGFloat) async -> [Found] {
        var previous: [MenuBarItem] = []
        var landed: [Found] = []
        for _ in 0..<attemptLimit {
            landed = await scan(height: height).filter { reach ~= $0.item.frame.midX }
            if !landed.isEmpty, landed.map(\.item) == previous { return landed }
            previous = landed.map(\.item)
            try? await Task.sleep(for: .milliseconds(8))
        }
        Log.menuBar.error("Standalone bar: revealed items never settled in the bar")
        return landed
    }

    /// Waits for `elements` to leave the bar, so a cover lifting off them does not show them going.
    /// A hidden item's element has no frame.
    static func removal(of elements: [ItemElement]) async {
        for _ in 0..<attemptLimit {
            if elements.allSatisfy({ ClickForwarder.itemFrame(of: $0.element) == nil }) { return }
            try? await Task.sleep(for: .milliseconds(8))
        }
        let left = elements.compactMap { ClickForwarder.itemFrame(of: $0.element) }.map { "\($0)" }
        Log.menuBar.error("Standalone bar: still in the bar: \(left.joined(separator: ", "), privacy: .public)")
    }

    private static func id(of element: ItemElement) -> UInt32 {
        UInt32(truncatingIfNeeded: CFHash(element.element))
    }

    private static let attemptLimit = 30
}
