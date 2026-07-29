import AppKit
import BouncerFoundation
import CoreGraphics
import MenuBar
import Observation
import Settings

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
    private let settings: SettingsStore
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
    /// How long the panel takes to come out of the menu bar, or `nil` while animation is
    /// switched off. Read once per open, and used again to put the bar away.
    private var slide: TimeInterval?
    /// The order the section came back in when it was last revealed.
    ///
    /// The panel is drawn before the reveal, so the order the replicas go in has to be
    /// predicted — and the parked order is not always the answer: two items of the same width
    /// were measured trading places on the way back on screen. What the section did last time
    /// is the best guide there is, and it is replaced by the truth on every open.
    private var orderLastTime: [UInt32] = []

    public init(menuBar: MenuBarManager, settings: SettingsStore) {
        self.menuBar = menuBar
        self.settings = settings
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
        // Read once per open, so the bar leaves the way it arrived even if the preference
        // changes while it is up.
        slide = settings.preferences.animateBar ? settings.preferences.barAnimationDuration : nil

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

        // The panel is built where the section is about to land — the shelf over that stretch
        // of bar, the cover over it — and run out of the menu bar as one piece. It can be
        // built before the reveal because the landing is worked out rather than measured, and
        // because a replica's position within the shelf is the item's position within its own
        // section, which the reveal does not change: it moves the section, not its packing.
        //
        // Nothing of the real bar is disturbed while it comes down. The section is still
        // parked off the display, so the replicas cross empty menu bar, and only once the
        // cover has landed over that stretch are the real items brought back underneath it.
        let landing = MenuBarItemGeometry.landingStrip(for: parked, leftOf: all)
        cover.show(over: landing.insetBy(dx: -Self.coverBleed, dy: 0))
        bar.update(images: itemCapture.images)
        bar.show(MenuBarItemGeometry.packed(parked, into: landing, like: orderLastTime), below: landing)
        await runThePanelOut()

        let revealed = await reveal(hidden)
        guard let strip = MenuBarItemGeometry.coverRect(for: revealed) else {
            Log.menuBar.info("Standalone bar: the hidden section did not come back on screen")
            await abandonOpen(of: hidden)
            return
        }
        items = revealed
        orderLastTime = revealed.map(\.windowID)
        // Corrected onto where the section actually landed, now that it can be measured — a
        // move of nothing at all unless the landing was worked out wrong, and a glide rather
        // than a jump when it was. The cover is widened to match the shelf: the two stand for
        // the same items, so a cover narrower than the shelf reads as the shelf hanging out
        // past its own section.
        cover.settle(onto: strip.insetBy(dx: -Self.coverBleed, dy: 0), over: slide)
        bar.show(revealed, below: strip)
        // The items under the cover are painted over, not moved, and so still take clicks.
        shield.show(over: strip)

        finishOpening(of: hidden, from: PlacementWait.frames(of: hidden), over: strip)
    }

    /// Runs the panel down out of the menu bar: replicas first, cover behind them.
    ///
    /// Both halves travel the height of the shelf's window — the shelf's own height plus the
    /// band it comes through — in one animation group, which is what keeps them a single
    /// panel. Awaited, because the cover being over the section is what makes it safe to
    /// reveal, and eased out so the panel settles rather than stopping dead.
    private func runThePanelOut() async {
        guard let slide, let shelf = bar.panel else { return }
        let travel = bar.travel
        cover.park(by: travel)
        bar.park(by: travel)
        await Slide.run([shelf, cover.panel], to: .zero, over: slide, easing: .easeOut)
    }

    /// Takes the panel back into the menu bar, and returns once it has gone.
    ///
    /// Only ever called with the section already put away: the cover leaves with the panel, so
    /// anything it was hiding has to have stopped being there first.
    ///
    /// Eased at both ends rather than mirroring the way in. The reverse of an ease out is an
    /// ease in, which spends its slow half creeping and then throws the panel out of sight in
    /// the last few frames — the leaving is the part being watched, and it read as the bar
    /// vanishing rather than going.
    private func runThePanelIn() async {
        guard let slide, let shelf = bar.panel else { return }
        await Slide.run(
            [shelf, cover.panel],
            to: CGPoint(x: 0, y: bar.travel),
            over: slide,
            easing: .easeInEaseOut
        )
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

    /// Unwinds an open that failed after the panel came out and the section was revealed.
    ///
    /// Left alone, the panel stays over the bar and the boundary markers never come back.
    private func abandonOpen(of ids: Set<UInt32>) async {
        resolvingElements?.cancel()
        resolvingElements = nil
        menuBar.setVisibility(.collapsed)
        await PlacementWait.removal(of: ids)
        menuBar.setBoundaryMarkersVisible(true)
        // The panel is already out by this point, replicas and all, so it goes too.
        bar.hide()
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
        let replicated = Set(items.map(\.windowID))
        items = []
        resolvingElements?.cancel()
        resolvingElements = nil

        itemCapture.stop()

        // The section goes away first, underneath the panel that is still over it — the open
        // run backwards. The cover leaves with the panel it is half of, so anything it was
        // hiding has to be gone by then, or the items sit in plain sight until the divider
        // catches up.
        menuBar.setVisibility(.collapsed)
        await PlacementWait.removal(of: replicated)
        // Before the panel goes rather than after: showing a marker changes the divider's
        // width, and every item to the left of it shifts to make room. Cheaper to do that
        // while something is still over it than to find out it shows.
        menuBar.setBoundaryMarkersVisible(true)
        await runThePanelIn()
        bar.hide()
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
