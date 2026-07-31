import AppKit
import BouncerFoundation
import MenuBar

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
    /// The tail of a handover: the user has let go, but the bar has not stopped moving.
    private var isFinishing = false
    /// From the press until the bar is back at rest, which is what `lookAgain` has to stay out of:
    /// it watches for the same release that ends a handover, and both would settle the bar.
    var isBusy: Bool { isUnderway || isFinishing }

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
    /// The pending look at what the section holds, after a drag that did not start on a replica.
    private var looking: Task<Void, Never>?
    /// What the section holds. Kept up to date as the user drags things into and out of it.
    private var section: Set<UInt32> = []
    /// Bouncer's own windows by name, and the hidden divider among them. Resolved by `nameOurs`
    /// when a drag begins, and reused for every frame of it.
    private var ours: [UInt32: String] = [:]
    private var dividerID: UInt32?
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
    ///
    /// - Returns: whether there is still a section to hang the panel off. Nothing left means the
    ///   user has dragged the last item out of it, and the bar has nothing to be a bar of.
    @discardableResult
    func settleBack(
        onto settled: [MenuBarItem], over slide: TimeInterval?, from before: [MenuBarItem]
    ) -> Bool {
        let joined = Set(settled.map(\.windowID)).subtracting(before.map(\.windowID))
        if !joined.isEmpty {
            Log.menuBar.info("Standalone bar: \(joined.count, privacy: .public) items joined the section")
            capture.capture(settled)
            bar.update(images: capture.images)
        }
        // Reported before the strip is asked for, so an emptied section is reported as empty
        // rather than leaving its owner holding items that have left.
        onSectionChanged?(settled, joined)
        guard let strip = MenuBarItemGeometry.coverRect(for: settled) else { return false }
        // Every part of the panel, so this is the whole answer to "the section has moved or
        // changed". `followTheShift` has nothing else to put the shelf back under its items with.
        bar.show(settled, below: strip)
        cover.settle(onto: strip.insetBy(dx: -ReplicaBar.padding, dy: 0), over: slide)
        shield.show(over: strip)
        return true
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
    /// 120 ms this waits before pressing. Ignoring events lands within 30 ms.
    func begin(on item: MenuBarItem, from section: [MenuBarItem]) async {
        guard !isUnderway else { return }
        self.section = Set(section.map(\.windowID))
        nameOurs()
        isUnderway = true
        Log.menuBar.info("Standalone bar: handing the drag to the real item")
        // Stood down without waiting: the beat it takes to stop hit-testing is spent reading the
        // item's frame and taking the pointer up to it, and `settled` waits out whatever is left
        // of it immediately before the press — which is the only part of this it has to be out of.
        shield.standDown()
        guard await ItemHandoff.begin(on: item.windowID, once: shield.settled) else {
            Log.menuBar.error("Standalone bar: the item to hand over has gone")
            isUnderway = false
            // Back to swallowing. Stood down for a press that never happened, it would otherwise
            // leave every real item under the cover taking clicks nobody can see them take.
            if let strip = MenuBarItemGeometry.coverRect(for: section) { shield.show(over: strip) }
            return
        }
        Log.menuBar.info("Standalone bar: the real item is in the user's hand")
        // Its replica stops being drawn: the user is holding the real one, and two of the same
        // icon a row apart is one too many.
        bar.setInHand(item.windowID)
        following = Task { [weak self] in await self?.follow() }
        // Taken down by the first release it sees, before that release is passed on. A drop
        // delivers more than one `leftMouseUp` — measured at two, 1 ms apart — and one gesture
        // has to end the handover exactly once.
        releaseWatch = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let watch = self.releaseWatch else { return }
                NSEvent.removeMonitor(watch)
                self.releaseWatch = nil
                self.onRelease?()
            }
        }
    }

    /// Follows a drag the user began in the menu bar rather than on a replica.
    ///
    /// Bouncer is no part of that gesture — there is nothing to hand over, and nothing to land —
    /// but the panel still has to keep up with a bar rearranging itself underneath it. Without
    /// this the section stands still through the whole drag and jumps once, when `lookAgain`
    /// settles it.
    ///
    /// The item in hand draws itself out of the way: a dragged item leaves the status item layer,
    /// so the scanner stops seeing it and the panel follows what is left. Called on every frame of
    /// the drag and does nothing once the follow is up.
    func followAlong() {
        guard !isBusy, following == nil else { return }
        nameOurs()
        following = Task { [weak self] in await self?.follow() }
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

    /// Whether the user let go over the panel, rather than below it.
    ///
    /// Below the shelf is the system's own gesture for taking an item off the menu bar, and it is
    /// left alone: their release has already landed that, and carrying the item home would be
    /// Bouncer undoing a gesture that is none of its business. The item follows the pointer down
    /// out of the bar for the whole drag either way — which is what makes pulling one out read as
    /// pulling it out, and what has macOS draw its own preview for an item on its way off the bar.
    private var isOverThePanel: Bool { NSEvent.mouseLocation.y >= bar.bottomEdge }

    /// Draws the section where it now stands, and moves the cover with it.
    ///
    /// Called on every frame of a drag, which is why it may ask nothing expensive: `nameOurs` has
    /// already said which windows are Bouncer's, so this is one scan.
    ///
    /// The item in hand is not among them. A dragged item leaves the status item layer entirely —
    /// the system draws it in a window of its own, far above — so there is no frame to draw it at,
    /// and none is wanted: the user is holding the real one. The hole it is about to land in is
    /// covered all the same, because the strip is measured to the divider.
    private func drawTheSection() {
        guard let read = readTheSection(), let strip = read.strip else { return }
        bar.show(read.items, below: strip)
        // The cover comes with it. The two are one panel, and a cover left at its old width hangs
        // out past the shelf below it, over bar it is no longer hiding anything in.
        cover.show(over: strip.insetBy(dx: -ReplicaBar.padding, dy: 0))
    }

    /// Works out afresh what the section holds, and draws it.
    @discardableResult
    func showTheSection() -> [MenuBarItem] {
        guard let read = readTheSection() else {
            return StatusItemScanner.scan().filter { section.contains($0.windowID) }
        }
        if let strip = read.strip { bar.show(read.items, below: strip) }
        return read.items
    }

    /// What the section holds and the stretch of bar it occupies, read out of the window server.
    ///
    /// `nil` when there is no divider to measure from, which leaves the section exactly as it was
    /// — one drag out of date, rather than read off the wrong end of the bar. An empty section is
    /// a different answer and comes back as one: no items, and no strip to draw them over.
    private func readTheSection() -> (items: [MenuBarItem], strip: CGRect?)? {
        let all = StatusItemScanner.scan()
        guard let dividerID, let edge = all.first(where: { $0.windowID == dividerID })?.frame.minX else {
            Log.menuBar.error("Standalone bar: the divider is not in the bar — leaving the section alone")
            return nil
        }
        let live = all.filter { ours[$0.windowID] == nil && $0.frame.minX >= 0 }
        let items = MenuBarItemGeometry.section(live, leftOf: edge)
        section = Set(items.map(\.windowID))
        return (items, MenuBarItemGeometry.coverRect(for: items, upTo: edge))
    }

    /// Names Bouncer's own windows, and picks the hidden divider out of them.
    ///
    /// Once per drag rather than once per frame: naming windows costs a second enumeration of
    /// every window on the system, and nothing about Bouncer's own items changes while the user
    /// is dragging one of somebody else's.
    private func nameOurs() {
        ours = StatusItemScanner.bouncersOwn()
        dividerID = ours.first { $0.value == StatusItemPosition.hiddenDividerName }?.key
    }

    /// Looks again at what the section holds, after a Cmd-drag that did not start on a replica.
    ///
    /// Dragging an item *into* the section can only be done in the real menu bar — the shelf has
    /// nothing to drag from — so the one signal there is is a release with Cmd held anywhere.
    ///
    /// Skipped whenever a handover is busy, at both ends of the wait: that release is the one
    /// ending it, and `end` is already settling the bar around it. The pending look is held so a
    /// drop's several releases coalesce into one, and so closing can call it off.
    func lookAgain(around known: [MenuBarItem], over slide: TimeInterval?) {
        guard !isBusy else { return }
        looking?.cancel()
        looking = Task { [weak self] in
            // Measured at 230 to 410 ms for the bar to stop moving after a drop.
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, let self, !isBusy else { return }
            // The follow is left going across the settle, as it is in `end`: the bar is still
            // moving, and the panel should keep up with it rather than wait out a timer.
            following?.cancel()
            following = nil
            settleBack(onto: refresh(around: known), over: slide, from: known)
        }
    }

    private func refresh(around known: [MenuBarItem]) -> [MenuBarItem] {
        section = Set(known.map(\.windowID))
        // A release the follow never saw — Cmd let go before the mouse, say — leaves nothing
        // named. Cheap once, at rest.
        if dividerID == nil { nameOurs() }
        return showTheSection()
    }

    /// Stops everything still running, without landing anything.
    ///
    /// For a close. A follow left going draws frames into a bar that is being taken down, and puts
    /// it back up behind the close — sized to a section on its way off screen and empty, because
    /// the pictures went with the close.
    func stop() {
        following?.cancel()
        following = nil
        looking?.cancel()
        looking = nil
        if let releaseWatch { NSEvent.removeMonitor(releaseWatch) }
        releaseWatch = nil
        isUnderway = false
    }

    /// Ends the drag, waits for the bar to stop moving, and reports the section as it now stands.
    ///
    /// - Returns: the settled section, or `nil` when there was no handover of this call's to end —
    ///   which is not the same answer as an empty section, and must not be read as one. A drop
    ///   delivers more than one release, and a bar closed for having nothing left in it is the
    ///   wrong thing to do with the second.
    func end() async -> [MenuBarItem]? {
        guard isUnderway, !isFinishing else { return nil }
        isFinishing = true
        defer { isFinishing = false }
        Log.menuBar.info("Standalone bar: the user let go — landing the item")
        if let releaseWatch { NSEvent.removeMonitor(releaseWatch) }
        releaseWatch = nil
        await ItemHandoff.end(carryingBack: isOverThePanel)
        // Drawn again from the moment it exists again. The follow is left running across the
        // settle for exactly this: an item in hand has no frame to draw it at, so the shelf has a
        // hole in it until the item is back in the bar, and the hole should close the moment it
        // is — not when some timer says the bar has probably finished moving.
        bar.setInHand(nil)
        // Measured at 230 to 410 ms for the bar to settle after a drop.
        try? await Task.sleep(for: .milliseconds(450))
        // Called off while it waited, by a close. The section is on its way off the display, so
        // reading it now answers "empty" for the wrong reason.
        guard isUnderway else { return nil }
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
