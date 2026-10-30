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
        await found()
            .map { found in
                let frame = CGRect(x: found.frame.minX, y: 0, width: found.frame.width, height: height)
                return (MenuBarItem(windowID: id(of: found.element), frame: frame), found.element)
            }
            .sorted { $0.item.frame.minX < $1.item.frame.minX }
    }

    /// Where every status item but Bouncer's own sits, as Accessibility reports it. One macOS had
    /// no room for sits above the display.
    static func frames() async -> [CGRect] {
        await found().map(\.frame)
    }

    /// Every item once the open chevron has drawn the overflow left of `edge`.
    ///
    /// A bounded poll, like `revealed`: the overflow was measured reporting its final places 70 to
    /// 180 ms after the press, while it still slides out of the notch, and in batches up to 100 ms
    /// apart. So it has to hold still for longer than that gap.
    static func overflowed(leftOf edge: CGFloat) async -> [CGRect] {
        var previous: [CGRect] = []
        var stillFor = 0
        var all: [CGRect] = []
        for _ in 0..<attemptLimit {
            all = await frames()
            let left = all.filter { $0.minY >= 0 && $0.maxX <= edge }.sorted { $0.minX < $1.minX }
            stillFor = !left.isEmpty && left == previous ? stillFor + 1 : 0
            if stillFor == stillReadings { return all }
            previous = left
            try? await Task.sleep(for: .milliseconds(15))
        }
        Log.menuBar.error("Standalone bar: the overflow never settled left of the notch")
        return all
    }

    /// Waits for the bar to be laid out again after the divider changed width. A bounded poll.
    static func change(from frames: [CGRect]) async {
        for _ in 0..<attemptLimit {
            if await self.frames() != frames { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private static func found() async -> [(frame: CGRect, element: ItemElement)] {
        let own = getpid()
        let pids = await MainActor.run {
            NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy != .prohibited && $0.processIdentifier != own }
                .map(\.processIdentifier)
        }
        // One task per app, as `ClickForwarder` does: an app that has stopped answering must not
        // hold up the ones that do.
        return await withTaskGroup(of: [(frame: CGRect, element: ItemElement)].self) { group in
            for pid in pids {
                group.addTask { ClickForwarder.statusItems(of: pid) }
            }
            var all: [(frame: CGRect, element: ItemElement)] = []
            for await items in group { all.append(contentsOf: items) }
            return all
        }
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

    private static func id(of element: ItemElement) -> UInt32 {
        UInt32(truncatingIfNeeded: CFHash(element.element))
    }

    private static let attemptLimit = 30
    /// Readings 15 ms apart that make the overflow's batches gap of 100 ms.
    private static let stillReadings = 8
}
