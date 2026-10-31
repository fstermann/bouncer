import AppKit
import BouncerFoundation
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
/// The items are photographed before any of that, while they are still parked, so the pictures
/// owe nothing to the reveal. The reveal is for the menus alone: one opens out of the real item,
/// and an item off the display opens its menu off the display with it.
///
/// Nothing runs while the bar is closed. The cover and the bar window go away on `close`, and
/// the divider goes back to doing the hiding.
@MainActor
@Observable
public final class StandaloneBarController {
    public private(set) var isOpen = false

    let menuBar: MenuBarManager
    let settings: SettingsStore
    let itemCapture = ItemCapture()
    let cover = CoverWindow()
    let shield = ClickShield()
    let bar = ReplicaBar()
    let menus = MenuWatcher()
    private let handover: Handover

    /// Watches for the pointer leaving the bar.
    private var pointerObservation: Any?
    /// The items being replicated, held so a click can be mapped back to a real one.
    var items: [MenuBarItem] = []
    /// Whether a menu opened from a replica is showing.
    var isMenuOpen = false
    /// When the bar puts itself away, and what it is waiting for.
    let closing = BarClosing()
    /// The bounded wait for the recording indicator to shift the bar, while it is opening.
    private var settling: Task<Void, Never>?
    /// What a replica's click is delivered to, resolved while the bar opens and awaited only
    /// when one is clicked.
    var resolvingElements: Task<[UInt32: ItemElement], Never>?
    /// How long the panel takes to come out of the menu bar, or `nil` while animation is
    /// switched off. Read once per open, and used again to put the bar away.
    var slide: TimeInterval?
    /// The order the section came back in when it was last revealed.
    ///
    /// The panel is drawn before the reveal, so the order the replicas go in has to be
    /// predicted — and the parked order is not always the answer: two items of the same width
    /// were measured trading places on the way back on screen. What the section did last time
    /// is the best guide there is, and it is replaced by the truth on every open.
    private var orderLastTime: [UInt32] = []
    private let indicator = PrivacyIndicator()
    let tab = NotchTab()
    /// Whether this open went the macOS 27 way (`openInTheBar`), so closing it does too.
    var isInTheBar = false
    /// How the section lay when last closed in the bar, which the next open splits and bands it by.
    var lastLayout: NotchSplit.Layout? { get { .saved } set { NotchSplit.Layout.saved = newValue } }
    var appSwitches: NSObjectProtocol?
    /// What a todo page switching back hands the next open, to take the notch's shape before it shows.
    var shapeOnOpen: (@MainActor (CGRect) async -> Void)?

    public init(menuBar: MenuBarManager, settings: SettingsStore) {
        self.menuBar = menuBar
        self.settings = settings
        handover = Handover(bar: bar, cover: cover, shield: shield, capture: itemCapture)
        bar.onClick = { [weak self] item in self?.forward(to: item) }
        bar.onHandoff = { [weak self] item in
            guard self?.isInTheBar == false else { return }
            Task { await self?.handover.begin(on: item, from: self?.items ?? []) }
        }
        bar.onArm = { [weak self] in self?.shield.standDown() }
        bar.onDisarm = { [weak self] in self?.shield.standUp() }
        handover.onRelease = { [weak self] in Task { await self?.finishHandingOver() } }
        handover.onEmptied = { [weak self] in Task { await self?.closeOverNothing() } }
        handover.onSectionChanged = { [weak self] settled, joined in
            self?.items = settled
            self?.orderLastTime = settled.map(\.windowID)
            if !joined.isEmpty { self?.resolveElements(for: Set(settled.map(\.windowID))) }
        }
    }

    /// Whether an `open` is underway, so a second click mid-open starts nothing.
    private var isOpening = false
    /// The same for `close`, which is not simply the absence of `isOpen`: closing clears that flag
    /// and then waits for the section to go off screen, and an open started in that gap has its
    /// cover pulled down by the close still finishing.
    private var isClosing = false

    /// Whether the bar photographs items: not on macOS 27, where they stay in the menu bar.
    public static var needsScreenRecording: Bool {
        if #available(macOS 27, *) { return false }
        return true
    }

    public func toggle() async {
        isOpen ? await close() : await open()
    }

    /// Reveals the hidden section, hides it again behind a cover, and replicates it below.
    public func open(closingWhenLeft: Bool = false, animated: Bool = true) async {
        guard !isOpen, !isOpening, !isClosing else { return }
        isOpening = true
        defer { isOpening = false }
        if #available(macOS 27, *) {
            let shape = shapeOnOpen
            shapeOnOpen = nil
            return await openInTheBar(closingWhenLeft: closingWhenLeft, takingShape: shape)
        }
        guard CGPreflightScreenCaptureAccess() else {
            Log.menuBar.error("Standalone bar: Screen Recording not granted")
            return
        }
        guard ItemCapture.isAvailable else {
            Log.menuBar.error("Standalone bar: this macOS cannot photograph the items")
            return
        }
        Log.menuBar.info("Standalone bar: opening")
        // Read once per open, so the bar leaves the way it arrived even if the preference changes.
        slide = settings.preferences.animateBar ? settings.preferences.barAnimationDuration : nil
        closing.closesOnLeave = closingWhenLeft

        // Which items are hidden has to be settled *before* revealing them, because once
        // they are back on screen they are indistinguishable from the ones that were
        // visible all along. Identity survives the move; position does not.
        let all = MenuBarItemGeometry.excludingDividers(StatusItemScanner.scan())
        let section = indicator.section(of: all, screens: NSScreen.screens.map(\.frame), like: orderLastTime)
        let parked = section.items
        let hidden = Set(parked.map(\.windowID))
        guard !hidden.isEmpty else {
            Log.menuBar.info("Standalone bar: nothing is hidden — is the section already revealed?")
            return
        }

        // Photographed where they are, before anything moves. The pictures do not depend on
        // the items being on screen, only the menus do, so this runs while the bar is still
        // untouched — and it is what keeps the replicas out of the reveal's way entirely.
        await itemCapture.captureOnceDrawn(parked)

        // Before anything moves: the accessibility tree lags the window server after a layout
        // change, so an item looked up just after being revealed is matched against where it isn't.
        resolveElements(for: hidden)

        // The panel is built where the section is about to land — the shelf over that stretch
        // of bar, the cover over it — and run out of the menu bar as one piece. It can be
        // built before the reveal because the landing is worked out rather than measured, and
        // because a replica's position within the shelf is the item's position within its own
        // section, which the reveal does not change: it moves the section, not its packing.
        //
        // Nothing of the real bar is disturbed while it comes down. The section is still
        // parked off the display, so the replicas cross empty menu bar, and only once the
        // cover has landed over that stretch are the real items brought back underneath it.
        let landing = NotchCentring(menuBar: menuBar).landing(for: parked, leftOf: section.run)
        cover.show(over: landing.insetBy(dx: -Self.coverBleed, dy: 0))
        bar.update(images: itemCapture.images)
        bar.show(MenuBarItemGeometry.packed(parked, into: landing, like: section.order), below: landing)
        await Slide.panelOut(bar, cover, over: animated ? slide : nil)
        bar.setCrossing(false)

        let revealed = await NotchCentring(menuBar: menuBar).confirm(await reveal(hidden), in: landing, of: hidden)
        guard let strip = MenuBarItemGeometry.coverRect(for: revealed) else {
            Log.menuBar.info("Standalone bar: the hidden section did not come back on screen")
            await abandonOpen(of: indicator.parkable(parked))
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
        return indicator.learning(from: MenuBarItemGeometry.excludingDividers(StatusItemScanner.scan())
            .filter { hidden.contains($0.windowID) && $0.frame.minX >= 0 })
    }

    /// How far past the section the cover reaches at each end: the same as the shelf below
    /// it, so the two are exactly as wide as each other.
    static let coverBleed = ReplicaBar.padding

    /// Resolves what each replica's click goes to, in the background: the sweep spends a second
    /// on any app that has stopped answering, so it is awaited only once one is clicked.
    private func resolveElements(for ids: Set<UInt32>) {
        resolvingElements?.cancel()
        resolvingElements = Task.detached { await ClickForwarder.elements(for: Array(ids)) }
    }

    /// Marks the bar open and installs the two things that outlive `open`: the watch for the
    /// pointer leaving, and the one bounded wait for the recording indicator to shift the
    /// items out from under the replicas.
    func finishOpening(of hidden: Set<UInt32>, from before: [UInt32: CGRect], over strip: CGRect) {
        isOpen = true
        watchForThePointerLeaving()
        // A menu opened from a replica belongs to the app it came from, and activating that
        // app must not pull the bar out from under the menu.
        closing.start(for: settings.preferences.autoRehide) { [weak self] in
            guard let self, isOpen, !isMenuOpen, !handover.isUnderway else { return }
            Task { await self.close() }
        }
        // Following the shift reads the window list, which macOS 27 no longer fills, and there
        // are no replicas to move there anyway.
        if !isInTheBar {
            settling = Task { [weak self] in
                await self?.followTheShift(of: hidden, from: before)
            }
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
    /// A replica has to sit under the item it stands for: the menu comes out of the real item, not
    /// its picture, so a bar left where the items *were* sends the user to click an icon whose
    /// menu opens elsewhere. The one shift there is to follow, and nothing is left running after.
    private func followTheShift(of ids: Set<UInt32>, from before: [UInt32: CGRect]) async {
        await PlacementWait.stillness(of: ids, movedFrom: before)
        guard !Task.isCancelled, isOpen else { return }

        let settled = MenuBarItemGeometry.excludingDividers(StatusItemScanner.scan())
            .filter { ids.contains($0.windowID) && $0.frame.minX >= 0 }
        guard settled.map(\.frame) != items.map(\.frame) else { return }
        handover.settleBack(onto: settled, over: nil, from: items)
    }

    /// Puts everything away and hands hiding back to the divider.
    public func close(animated: Bool = true) async {
        guard isOpen else { return }
        isOpen = false
        isClosing = true
        defer { isClosing = false }

        if let pointerObservation { NSEvent.removeMonitor(pointerObservation) }
        pointerObservation = nil
        // First, so nothing the handover has running draws into a bar that is being taken down.
        handover.stop()
        closing.stop()
        settling?.cancel()
        settling = nil
        menus.stop()
        isMenuOpen = false
        let replicated = indicator.parkable(items)
        items = []
        resolvingElements?.cancel()
        resolvingElements = nil
        itemCapture.stop()
        if isInTheBar {
            isInTheBar = false
            await closeInTheBar(animated: animated)
            menuBar.isRevealHeld = false
            return
        }

        // The section goes away underneath the panel, which only uncovers the bar once it has:
        // the cover leaves with the panel it is half of.
        await Slide.panelIn(bar, cover, over: animated ? slide : nil) { [menuBar] in
            menuBar.setVisibility(.collapsed)
            await PlacementWait.removal(of: replicated)
            // Before the panel goes: a marker widens the divider, shifting the items left of it.
            menuBar.setBoundaryMarkersVisible(true)
        }
        bar.hide()
        cover.hide()
        shield.hide()
        // Released last, so releasing it cannot re-arm a rehide for a section that is on its
        // way off screen anyway.
        menuBar.isRevealHeld = false
    }

    /// Takes the bar back over the rearranged section — or away, once the last item has left it.
    private func finishHandingOver() async {
        guard let settled = await handover.end() else { return }
        if !handover.settleBack(onto: settled, over: slide, from: items) {
            await closeOverNothing()
        }
    }

    /// The last item has been dragged out. A shelf of nothing over a cover hiding nothing is not
    /// a bar; it is a stretch of menu bar that swallows clicks for no reason.
    private func closeOverNothing() async {
        Log.menuBar.info("Standalone bar: the section is empty — closing")
        await close()
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
    /// is open. It is also the only watch on the pointer there is, so the two signals a
    /// rearrangement gives off are read here as well: a Cmd-drag up in the bar, and the release
    /// that ends it.
    private func watchForThePointerLeaving() {
        let watched: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseUp]
        pointerObservation = NSEvent.addGlobalMonitorForEvents(matching: watched) { event in
            MainActor.assumeIsolated {
                switch event.type {
                case .mouseMoved: self.closeIfThePointerHasLeft()
                // A Cmd-drag up in the bar is the user rearranging it, whether or not it began on
                // a replica. The panel follows either way, or it stands still through the drag and
                // jumps once at the end of it.
                case .leftMouseDragged where self.isRearranging(event):
                    if self.isInTheBar { self.followDragInTheBar() } else { self.handover.followAlong() }
                // Any release ends whatever drag the follow was following — Cmd or not, since Cmd
                // let go before the mouse ends it just the same. The look stands itself down when
                // no follow is up; on macOS 27 the band is refitted.
                case .leftMouseUp where self.isInTheBar: Task { await self.refitInTheBar() }
                case .leftMouseUp: self.handover.lookAgain(around: self.items, over: self.slide)
                default: break
                }
            }
        }
        // It may have left while the bar was opening, before there was a watch to see it go.
        closeIfThePointerHasLeft()
    }

    /// Whether a drag in flight could be moving a status item: Cmd held, and the pointer still up
    /// in the bar. Anything else — a window dragged across the desktop — is none of Bouncer's
    /// business, and following it would be a poll running for nothing.
    private func isRearranging(_ event: NSEvent) -> Bool {
        event.modifierFlags.contains(.command) && NSEvent.mouseLocation.y >= panelBottomEdge
    }

    /// A menu opened from the bar hangs below it, so reaching into one must not dismiss the
    /// bar out from under the pointer.
    ///
    /// Leaving is given a moment to be taken back. Overshooting the bar on the way to it, or
    /// dipping below it on the way across, should not put it away — and the pointer coming
    /// back cancels the close before it happens.
    func closeIfThePointerHasLeft() {
        // Not mid-handoff: the pointer is up in the menu bar, where the user has taken it.
        let hasLeft = isOpen && !isMenuOpen && !handover.isUnderway
            && NSEvent.mouseLocation.y < panelBottomEdge
        guard hasLeft else {
            closing.pointerReturned()
            return
        }
        closing.pointerLeft(for: settings.preferences.autoRehide) { [weak self] in
            guard let self else { return }
            // On macOS 27 the user clicks the real items, whose menus hang below the bar, and the
            // pointer reaching into one must not take the section away. The next move asks again.
            if isInTheBar, ItemMenus.isShowing {
                closing.pointerReturned()
                return
            }
            Task { await self.close() }
        }
    }

    /// The bottom of whatever the bar has drawn below the menu bar, in AppKit coordinates.
    private var panelBottomEdge: CGFloat { isInTheBar ? tab.bottomEdge : bar.bottomEdge }
}
