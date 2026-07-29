import AppKit
import BouncerFoundation
import CoreGraphics
import MenuBar
import Observation

/// Opens and closes the standalone bar.
///
/// The whole feature is an inversion of how Bouncer normally hides things. Bouncer's
/// dividers hide a section by pushing it past the edge of the display; this reveals it into
/// its ordinary place, covers that stretch of bar, and draws the items again a row lower. The
/// section is hidden from the eye and fully alive to a click at the same time.
///
/// The items are photographed before any of that, while they are still parked, so the
/// pictures owe nothing to the reveal. The reveal is for the menus alone: one opens out of
/// the real item, and an item off the display opens its menu off the display with it.
///
/// Nothing runs while the bar is closed. The cover and the bar window go away on `close`, and
/// the divider goes back to doing the hiding.
@MainActor
@Observable
public final class StandaloneBarController {
    public private(set) var isOpen = false

    /// How long the pointer may be away before the bar gives up on it coming back.
    private static let graceBeforeClosing = Duration.milliseconds(700)

    private let menuBar: MenuBarManager
    private let itemCapture = ItemCapture()
    private let cover = CoverWindow()
    private let shield = ClickShield()
    private let bar = ReplicaBar()
    private let menus = MenuWatcher()

    /// Watches for the pointer leaving the bar.
    private var pointerObservation: Any?
    /// The items being replicated, held so a click can be mapped back to a real one.
    private var items: [MenuBarItem] = []
    /// Whether a menu opened from a replica is showing.
    private var isMenuOpen = false
    /// The pending close, while the pointer is away but could still come back.
    private var closing: Task<Void, Never>?
    /// The bounded wait for the recording indicator to shift the bar, while it is opening.
    private var settling: Task<Void, Never>?
    /// What a replica's click is delivered to, resolved while the bar opens and awaited only
    /// when one is clicked.
    private var resolvingElements: Task<[UInt32: ItemElement], Never>?

    public init(menuBar: MenuBarManager) {
        self.menuBar = menuBar
        bar.onClick = { [weak self] item in
            self?.forward(to: item)
        }
    }

    /// Whether an `open` is underway, so a second click mid-open starts nothing.
    private var isOpening = false
    /// The same for `close`, which is not simply the absence of `isOpen`: closing clears that
    /// flag first and then waits for the section to go off screen, and an open started in
    /// that gap has its cover pulled down by the close that is still finishing.
    private var isClosing = false

    public func toggle() async {
        isOpen ? await close() : await open()
    }

    /// Reveals the hidden section, hides it again behind a cover, and replicates it below.
    public func open() async {
        guard !isOpen, !isOpening, !isClosing else { return }
        isOpening = true
        defer { isOpening = false }
        guard CGPreflightScreenCaptureAccess() else {
            Log.menuBar.error("Standalone bar: Screen Recording not granted")
            return
        }
        guard ItemCapture.isAvailable else {
            Log.menuBar.error("Standalone bar: this macOS cannot photograph the items")
            return
        }
        Log.menuBar.info("Standalone bar: opening")

        // Which items are hidden has to be settled *before* revealing them, because once
        // they are back on screen they are indistinguishable from the ones that were
        // visible all along. Identity survives the move; position does not.
        let all = MenuBarItemGeometry.excludingDividers(StatusItemScanner.scan())
        let parked = MenuBarItemGeometry.offScreen(all, screens: NSScreen.screens.map(\.frame))
        let hidden = Set(parked.map(\.windowID))
        guard !hidden.isEmpty else {
            Log.menuBar.info("Standalone bar: nothing is hidden — is the section already revealed?")
            return
        }

        // Photographed where they are, before anything moves. The pictures do not depend on
        // the items being on screen, only the menus do, so this runs while the bar is still
        // untouched — and it is what keeps the replicas out of the reveal's way entirely.
        itemCapture.capture(parked)

        // Covered before anything moves. Revealing is what puts the items back on screen, so
        // a cover that arrives late shows them in the gap.
        //
        // Over the stretch the section is about to land in, not over the whole bar: the rest
        // of the bar is not hiding anything and has no business being painted over.
        cover.show(over: landingStrip(leftOf: all, forWide: parked))

        // Resolved before anything moves, and left to run across the reveal. The
        // accessibility tree lags the window server by a moment after a layout change, so an
        // item looked up just after being revealed is matched against where it no longer is;
        // asked for now, while the bar has been still, every item is found. The elements
        // stay valid once the items move — it is only their positions that go stale.
        //
        // Never awaited here. The sweep spends a second on any app that has stopped
        // answering — a fixed timeout that was being paid on every open — and a replica needs
        // its element only once one is clicked.
        resolvingElements = Task.detached { await ClickForwarder.elements(for: Array(hidden)) }

        let revealed = await reveal(hidden)
        guard let strip = MenuBarItemGeometry.coverRect(for: revealed) else {
            Log.menuBar.info("Standalone bar: the hidden section did not come back on screen")
            await abandonOpen(of: hidden)
            return
        }
        items = revealed
        // Tightened to where the section actually landed, now that it can be measured, and
        // widened to match the shelf: the two stand for the same items, so a cover narrower
        // than the shelf reads as the shelf hanging out past its own section.
        cover.show(over: strip.insetBy(dx: -Self.coverBleed, dy: 0))
        // The items under the cover are painted over, not moved, and so still take clicks.
        shield.show(over: strip)

        let beforeCapture = PlacementWait.frames(of: hidden)

        // Shown at the positions the items hold now. Anything arriving in the bar — the
        // recording indicator a capture earns, most often — pushes every item along, so these
        // positions are not guaranteed to last; `followTheShift` moves the bar afterwards on
        // the occasions they do not.
        bar.update(images: itemCapture.images)
        bar.show(revealed, below: strip)

        finishOpening(of: hidden, from: beforeCapture, over: strip)
    }

    /// Reveals the section into the menu bar and reads back where its items landed.
    ///
    /// The items have no frames worth reading while they are off the display, so where the
    /// replicas go depends on them being back — and on them staying back, which is what the
    /// hold is for: auto-rehide would otherwise put the section away underneath a bar that is
    /// still open. The boundary marker goes with them: it points at where hiding ends in a bar
    /// the user is not being shown.
    private func reveal(_ hidden: Set<UInt32>) async -> [MenuBarItem] {
        menuBar.isRevealHeld = true
        menuBar.setBoundaryMarkersVisible(false)
        menuBar.setVisibility(.revealed)
        await PlacementWait.placement(of: hidden)
        return MenuBarItemGeometry.excludingDividers(StatusItemScanner.scan())
            .filter { hidden.contains($0.windowID) && $0.frame.minX >= 0 }
    }

    /// Where the section is about to land, before it has.
    ///
    /// The cover has to be up before the reveal — that is what keeps the items from being
    /// seen — so the strip cannot be measured, only predicted. Items come back immediately
    /// left of the run of items already on screen, so the right edge is known exactly; the
    /// width is their own plus room for the gaps between them, which is guesswork, and
    /// covering a little too much costs nothing but a stretch of empty bar.
    private func landingStrip(leftOf all: [MenuBarItem], forWide parked: [MenuBarItem]) -> CGRect {
        let width = parked.map(\.frame.width).reduce(0, +) * Self.landingSlack
        let height = parked.map(\.frame.height).max() ?? 0
        return CGRect(x: leftEdgeOfTheRun(in: all) - width, y: 0, width: width, height: height)
    }

    /// The left edge of the run of items at the right of the bar.
    ///
    /// Not simply the leftmost item on screen: a collapsed divider sits alone at the far left,
    /// and anchoring on that puts the cover off the display, where it hides nothing at all.
    /// Walked from the right instead, stopping at the first gap too wide to be the space
    /// between two neighbours.
    private func leftEdgeOfTheRun(in all: [MenuBarItem]) -> CGFloat {
        let onScreen = all.filter { $0.frame.minX >= 0 }.sorted { $0.frame.minX > $1.frame.minX }
        guard var edge = onScreen.first?.frame.minX else { return 0 }
        for item in onScreen.dropFirst() {
            guard edge - item.frame.maxX < Self.widestGapInARun else { break }
            edge = item.frame.minX
        }
        return edge
    }

    /// More space than two neighbouring items ever leave between them.
    private static let widestGapInARun: CGFloat = 80

    /// How much wider than the items themselves the predicted strip is drawn, to allow for
    /// the gaps between them.
    private static let landingSlack: CGFloat = 1.3

    /// How far past the section the cover reaches at each end: the same as the shelf below
    /// it, so the two are exactly as wide as each other.
    private static let coverBleed = ReplicaBar.padding

    /// Marks the bar open and installs the two things that outlive `open`: the watch for the
    /// pointer leaving, and the one bounded wait for the recording indicator to shift the
    /// items out from under the replicas.
    private func finishOpening(of hidden: Set<UInt32>, from before: [UInt32: CGRect], over strip: CGRect) {
        isOpen = true
        watchForThePointerLeaving()
        settling = Task { [weak self] in
            await self?.followTheShift(of: hidden, from: before)
        }
        let width = Int(strip.width)
        Log.menuBar.info(
            "Standalone bar: open, \(self.items.count, privacy: .public) items over \(width, privacy: .public) pt")
    }

    /// Unwinds an open that failed after the cover went up and the section was revealed.
    ///
    /// Left alone, the cover stays over the bar as a still picture and the boundary markers
    /// never come back.
    private func abandonOpen(of ids: Set<UInt32>) async {
        resolvingElements?.cancel()
        resolvingElements = nil
        menuBar.setVisibility(.collapsed)
        await PlacementWait.removal(of: ids)
        menuBar.setBoundaryMarkersVisible(true)
        cover.hide()
        shield.hide()
        menuBar.isRevealHeld = false
    }

    /// Moves the bar to wherever the recording indicator pushed the items.
    ///
    /// A replica has to sit under the item it stands for: the menu comes out of the real
    /// item, not its picture, so a bar left where the items *were* sends the user to click an
    /// icon whose menu opens somewhere else. This is the one shift there is to follow — it
    /// ends when the indicator has landed, and nothing is left running after it.
    private func followTheShift(of ids: Set<UInt32>, from before: [UInt32: CGRect]) async {
        await PlacementWait.stillness(of: ids, movedFrom: before)
        guard !Task.isCancelled, isOpen else { return }

        let settled = MenuBarItemGeometry.excludingDividers(StatusItemScanner.scan())
            .filter { ids.contains($0.windowID) && $0.frame.minX >= 0 }
        guard let strip = MenuBarItemGeometry.coverRect(for: settled),
              settled.map(\.frame) != items.map(\.frame)
        else { return }

        items = settled
        bar.show(settled, below: strip)
        shield.show(over: strip)
    }

    /// Puts everything away and hands hiding back to the divider.
    public func close() async {
        guard isOpen else { return }
        isOpen = false
        isClosing = true
        defer { isClosing = false }

        if let pointerObservation { NSEvent.removeMonitor(pointerObservation) }
        pointerObservation = nil
        closing?.cancel()
        closing = nil
        settling?.cancel()
        settling = nil
        menus.stop()
        isMenuOpen = false
        bar.hide()
        let replicated = Set(items.map(\.windowID))
        items = []
        resolvingElements?.cancel()
        resolvingElements = nil

        itemCapture.stop()

        // The cover comes down last, once the section is off screen again. Taking it away
        // first leaves the items it was hiding sitting in the bar, in plain sight, until the
        // divider has pushed them off — the same flash as opening, in reverse.
        menuBar.setVisibility(.collapsed)
        await PlacementWait.removal(of: replicated)
        // Before the cover comes down rather than after: showing a marker changes the
        // divider's width, and every item to the left of it shifts to make room. Cheaper to
        // do that while something is still over it than to find out it shows.
        menuBar.setBoundaryMarkersVisible(true)
        cover.hide()
        shield.hide()
        // Released last, so releasing it cannot re-arm a rehide for a section that is on its
        // way off screen anyway.
        menuBar.isRevealHeld = false
    }

    /// Closes the bar once the pointer moves below it.
    ///
    /// In a full screen space the menu bar slides away the moment the pointer leaves the
    /// top, and takes the real items with it — leaving the replicas floating over somebody
    /// else's window. The window server reports nothing when that happens: the menu bar
    /// window stays on screen, at the same position, at full alpha. What it does report is
    /// the pointer, and the pointer is the reason the bar went away in the first place.
    ///
    /// Only the vertical edge counts, so moving along the menu bar to Bouncer's own icon
    /// leaves the bar up.
    ///
    /// Driven by the pointer moving rather than by a clock, and installed only while the bar
    /// is open.
    private func watchForThePointerLeaving() {
        pointerObservation = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { _ in
            MainActor.assumeIsolated { self.closeIfThePointerHasLeft() }
        }
    }

    /// A menu opened from the bar hangs below it, so reaching into one must not dismiss the
    /// bar out from under the pointer.
    ///
    /// Leaving is given a moment to be taken back. Overshooting the bar on the way to it, or
    /// dipping below it on the way across, should not put it away — and the pointer coming
    /// back cancels the close before it happens.
    private func closeIfThePointerHasLeft() {
        let hasLeft = isOpen && !isMenuOpen && NSEvent.mouseLocation.y < bar.bottomEdge
        guard hasLeft else {
            closing?.cancel()
            closing = nil
            return
        }
        guard closing == nil else { return }
        closing = Task { [weak self] in
            try? await Task.sleep(for: Self.graceBeforeClosing)
            guard !Task.isCancelled else { return }
            await self?.close()
        }
    }

    /// Opens the real item a replica stands for.
    ///
    /// The sweep that finds the elements is usually long finished by the first click; when it
    /// is not, this waits for it rather than holding every open behind it.
    private func forward(to item: MenuBarItem) {
        guard ClickForwarder.isPermitted else {
            Log.menuBar.error("Standalone bar: click ignored, Accessibility not granted")
            return
        }
        guard let resolving = resolvingElements else { return }
        Task { [weak self] in
            let elements = await resolving.value
            guard let self, let element = elements[item.windowID] else {
                Log.menuBar.error("Standalone bar: the clicked item cannot be reached")
                return
            }
            self.open(element)
        }
    }

    /// Presses an item's element and follows whatever menu it opens.
    private func open(_ element: ItemElement) {
        if let owner = ClickForwarder.owner(of: element) {
            menus.watch(pid: owner) { [weak self] isOpen in
                guard let self else { return }
                self.isMenuOpen = isOpen
                self.bar.setDimmed(isOpen)
                if !isOpen {
                    self.menus.stop()
                    // The pointer is usually deep in the menu that just closed.
                    self.closeIfThePointerHasLeft()
                }
            }
        }
        Task.detached { ClickForwarder.press(element) }
    }
}
