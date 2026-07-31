import AppKit
import BouncerFoundation

/// Gets Bouncer out of the way while the user rearranges the real menu bar.
///
/// A drag that begins on a replica is handed to the item it stands for, and from that moment the
/// menu bar is doing what it does for anybody: the user's own pointer moves the item and their
/// own release drops it. Bouncer's part is to get out of the way of the press, and then to keep
/// its hands off until they have let go.
///
/// Split from `StandaloneBarController` because it is a mode rather than a step: while it is
/// underway the bar stops deciding anything for itself.
@MainActor
final class Handover {
    /// Whether the user is rearranging the real bar right now.
    private(set) var isUnderway = false

    /// Called with the section as it now stands, and the items that have just joined it, so the
    /// bar's owner can keep what it holds by window ID in step.
    var onSectionChanged: (@MainActor ([MenuBarItem], Set<UInt32>) -> Void)?

    private let bar: ReplicaBar
    private let cover: CoverWindow
    private let shield: ClickShield
    private let capture: ItemCapture
    /// Mirrors the real bar into the shelf while the user rearranges it. Runs only inside the
    /// drag, and is cancelled by the release that ends it.
    private var following: Task<Void, Never>?
    /// What the section holds. Kept up to date as the user drags things into and out of it.
    private var section: Set<UInt32> = []
    /// Watches for the user letting go, wherever they are by then.
    ///
    /// Not left to the shelf's own `mouseUp`. The pointer is warped out of that window as the
    /// gesture begins and the window server takes the drag over, so a release delivered back to
    /// the view that started it is something to hope for rather than rely on — and if it never
    /// arrives, nothing ever ends the handover.
    private var releaseWatch: Any?

    /// Called when the user lets go.
    var onRelease: (@MainActor () -> Void)?

    init(bar: ReplicaBar, cover: CoverWindow, shield: ClickShield, capture: ItemCapture) {
        self.bar = bar
        self.cover = cover
        self.shield = shield
        self.capture = capture
    }

    /// Puts the panel back over the section once a drag has finished with it.
    ///
    /// The bar stays open, so one drag can follow another — and the section is whatever it now
    /// holds, which after a drag across its boundary may be one item more or one fewer. An item
    /// that has just arrived has never been photographed, so the pictures are taken again.
    func settleBack(onto settled: [MenuBarItem], over slide: TimeInterval?, from before: [MenuBarItem]) {
        guard let strip = MenuBarItemGeometry.coverRect(for: settled) else { return }
        let joined = Set(settled.map(\.windowID)).subtracting(before.map(\.windowID))
        if !joined.isEmpty {
            Log.menuBar.info("Standalone bar: \(joined.count, privacy: .public) items joined the section")
            capture.capture(settled)
            bar.update(images: capture.images)
        }
        onSectionChanged?(settled, joined)
        cover.settle(onto: strip.insetBy(dx: -ReplicaBar.padding, dy: 0), over: slide)
        shield.show(over: strip)
    }

    /// Hands the drag over.
    ///
    /// Almost nothing is stood down for it. The cover stays, so the menu bar is not seen
    /// rearranging itself; the shelf stays, because that is where the user is about to do the
    /// dragging and it is the window that will be told when they let go. What the user sees is
    /// the real item in hand, over Bouncer's own bar.
    ///
    /// The shield is the exception, and it is not *hidden* but told to ignore mouse events. That
    /// distinction is the difference between this working and not: the shield is the one window
    /// above the items that takes mouse events, so it swallows the press that starts the handoff,
    /// and `orderOut` was measured taking 150 to 300 ms to stop a window hit-testing against the
    /// 50 ms this waits before pressing. Ignoring events lands within 30 ms.
    func begin(on item: MenuBarItem, from section: [MenuBarItem]) async {
        guard !isUnderway else { return }
        self.section = Set(section.map(\.windowID))
        isUnderway = true
        Log.menuBar.info("Standalone bar: handing the drag to the real item")
        await shield.stopSwallowing()
        guard await ItemHandoff.begin(on: item.windowID) else {
            Log.menuBar.error("Standalone bar: the item to hand over has gone")
            isUnderway = false
            return
        }
        Log.menuBar.info("Standalone bar: the real item is in the user's hand")
        // Its replica stops being drawn: the user is holding the real one, and two of the same
        // icon a row apart is one too many.
        bar.setInHand(item.windowID)
        following = Task { [weak self] in await self?.follow() }
        releaseWatch = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            MainActor.assumeIsolated { self?.onRelease?() }
        }
    }

    /// Follows the real section into the shelf, frame by frame, for as long as the drag lasts.
    ///
    /// The shelf shows what the bar is doing rather than working out what it ought to be doing.
    /// That is the whole difference from what this replaced: there is no packing rule, no drop
    /// point and no order to predict, because the menu bar has already decided all of it and this
    /// is only reading the answer.
    ///
    /// A poll, and the second one in the feature. It is bounded by a drag the user is actively
    /// making, it stops on the release that ends that drag, and there is nothing to observe
    /// instead — the window server rearranges status items without saying so.
    private func follow() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled else { return }
            drawTheSection()
        }
    }

    /// Draws the section where it currently is, without asking again what it contains.
    ///
    /// Membership is deliberately *not* worked out here. Mid-drag the bar is halfway through
    /// rearranging itself, so items are momentarily further apart than they will end up — and a
    /// rule that reads gaps sees them leave the section one by one as the user drags past them,
    /// with nothing to bring them back, because the next reading is taken around what is left.
    private func drawTheSection() {
        let live = StatusItemScanner.scan().filter { section.contains($0.windowID) && $0.frame.minX >= 0 }
        guard let strip = MenuBarItemGeometry.coverRect(for: live) else { return }
        bar.show(live, below: strip)
        // The cover comes with it. The two are one panel, and while an item is in hand the section
        // really is that much narrower — a cover left at its old width hangs out past the shelf
        // below it, over bar it is no longer hiding anything in.
        cover.show(over: strip.insetBy(dx: -ReplicaBar.padding, dy: 0))
    }

    /// Puts the shelf over the section wherever it currently is.
    ///
    /// An item being dragged is not in the status item layer at all — the system draws it in a
    /// window of its own, far above — so while it is in hand there is simply no frame for it, and
    /// the shelf is drawn without it. Which is right: the user is holding it.
    /// Works out afresh what the section holds, and draws it.
    ///
    /// Only ever called with the bar at rest, because the answer is read off the gaps between
    /// items and those are meaningless while it is moving. The user is allowed to drag items
    /// across the section's boundary: one taken out is no longer packed with the rest, and one
    /// brought in is. `packedRun` answers that, once Bouncer's own items are named out of the way
    /// — the divider stands between the section and the visible run, and left in would bridge the
    /// two into one.
    @discardableResult
    func showTheSection() -> [MenuBarItem] {
        let ours = StatusItemScanner.bouncersOwn()
        let live = StatusItemScanner.scan()
            .filter { !ours.contains($0.windowID) && $0.frame.minX >= 0 }
        let run = MenuBarItemGeometry.packedRun(live, around: section)
        section = Set(run.map(\.windowID))
        guard let strip = MenuBarItemGeometry.coverRect(for: run) else { return run }
        bar.show(run, below: strip)
        return run
    }

    /// Looks again at what the section holds, after a Cmd-drag that did not start on a replica.
    ///
    /// Dragging an item *into* the section can only be done in the real menu bar — the shelf has
    /// nothing to drag from — so the one signal there is is a release with Cmd held anywhere.
    func lookAgain(around known: [MenuBarItem], over slide: TimeInterval?) async {
        guard !isUnderway else { return }
        // Measured at 230 to 410 ms for the bar to stop moving after a drop.
        try? await Task.sleep(for: .milliseconds(450))
        guard !isUnderway else { return }
        settleBack(onto: refresh(around: known), over: slide, from: known)
    }

    private func refresh(around known: [MenuBarItem]) -> [MenuBarItem] {
        guard !isUnderway else { return known }
        section = Set(known.map(\.windowID))
        return showTheSection()
    }

    /// Ends the drag, waits for the bar to stop moving, and reports the section as it now stands.
    @discardableResult
    func end() async -> [MenuBarItem] {
        guard isUnderway else { return [] }
        Log.menuBar.info("Standalone bar: the user let go — landing the item")
        if let releaseWatch { NSEvent.removeMonitor(releaseWatch) }
        releaseWatch = nil
        await ItemHandoff.end()
        // Drawn again from the moment it exists again. The follow is left running across the
        // settle for exactly this: an item in hand has no frame to draw it at, so the shelf has a
        // hole in it until the item is back in the bar, and the hole should close the moment it
        // is — not when some timer says the bar has probably finished moving.
        bar.setInHand(nil)
        // Measured at 230 to 410 ms for the bar to settle after a drop.
        try? await Task.sleep(for: .milliseconds(450))
        following?.cancel()
        following = nil
        let settled = showTheSection()
        isUnderway = false
        Log.menuBar.info("Standalone bar: the handover is finished")
        // The shield goes back over whatever the section has become — it stood down for the press
        // and would otherwise leave the real items taking clicks nobody can see them take.
        if let strip = MenuBarItemGeometry.coverRect(for: settled) { shield.show(over: strip) }
        return settled
    }
}
