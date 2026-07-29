import AppKit
import BouncerFoundation
import MenuBar
import Observation
import ScreenCaptureKit

/// Opens and closes the standalone bar.
///
/// The whole feature is an inversion of how Bouncer normally hides things. Bouncer's
/// dividers hide a section by pushing it past the edge of the display, and an item parked
/// there is no longer drawn, so it has no pixels to replicate. This does the opposite: it
/// reveals the section into its ordinary place, covers that stretch of menu bar with a
/// capture of the bar without the items, and draws the items again a row lower. The section
/// is hidden from the eye and fully alive to the capture at the same time.
///
/// Nothing runs while the bar is closed. The streams, the cover and the bar window all go
/// away on `close`, and the divider goes back to doing the hiding.
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
        Log.menuBar.info("Standalone bar: opening")

        // Which items are hidden has to be settled *before* revealing them, because once
        // they are back on screen they are indistinguishable from the ones that were
        // visible all along. Identity survives the move; position does not.
        let all = MenuBarItemGeometry.excludingDividers(StatusItemScanner.scan())
        let hidden = Set(MenuBarItemGeometry.offScreen(all, screens: NSScreen.screens.map(\.frame)).map(\.windowID))
        guard !hidden.isEmpty else {
            Log.menuBar.info("Standalone bar: nothing is hidden — is the section already revealed?")
            return
        }

        // Fetched once and used for both captures. Enumerating every window on the system is
        // the expensive half of a capture, and it was being paid for twice per open.
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false
        ) else {
            Log.menuBar.error("Standalone bar: no shareable content; is Screen Recording granted?")
            return
        }

        // Covered before anything moves, painted before it is shown, and never resized after.
        // Revealing is what puts the items back on screen, so a cover that arrives late, that
        // goes up empty, or that changes size once the section has been measured shows them —
        // in the gap, or in the frame it takes to redraw.
        //
        // The whole bar rather than the section, and nothing excluded from it: the items are
        // still off screen at this point, so a picture of the bar taken now is already a
        // picture of the bar without them. That ordering is what makes the cover correct —
        // sampled after the reveal it would contain the very items it has to hide.
        var bandImage: CGImage?
        if let band = menuBarBand(around: all) {
            bandImage = await BackgroundCapture.sample(rect: band, excluding: [], in: content)
            // Nothing to paint it with means no cover: the window is opaque, so it would go
            // up as a black strip across the whole bar.
            if let bandImage { coverBar(band, with: bandImage) }
        }

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
        // The items under the cover are painted over, not moved, and so still take clicks.
        shield.show(over: strip)

        let beforeCapture = PlacementWait.frames(of: hidden)
        await itemCapture.begin(revealed, in: content)

        // Shown as soon as there are pictures to show, at the positions the items hold now.
        // Capturing can put a recording indicator in the bar, and anything arriving in the bar
        // pushes every item along, so these positions are not guaranteed to last. Waiting that
        // out before showing anything cost more than half the open; `followTheShift` moves the
        // bar afterwards on the occasions it is needed.
        bar.update(images: itemCapture.images)
        bar.matchShade(to: bandImage)
        bar.show(revealed, below: strip)

        // Without a cover over the whole bar — no band to anchor on, or nothing to paint one
        // with — the section itself is covered, sampled now the items are on screen and so
        // with them left out explicitly.
        if bandImage == nil {
            await coverSection(strip, replicating: revealed)
        }

        finishOpening(of: hidden, from: beforeCapture, over: strip)
    }

    /// Reveals the section into the menu bar and reads back where its items landed.
    ///
    /// The items have no frames worth reading and no pixels at all while they are off the
    /// display, so everything after this depends on them being back — and on them staying
    /// back, which is what the hold is for: auto-rehide would otherwise put the section away
    /// underneath a bar that is still open. The boundary marker goes with them: it points at
    /// where hiding ends in a bar the user is not being shown.
    private func reveal(_ hidden: Set<UInt32>) async -> [MenuBarItem] {
        menuBar.isRevealHeld = true
        menuBar.setBoundaryMarkersVisible(false)
        menuBar.setVisibility(.revealed)
        await PlacementWait.placement(of: hidden)
        return MenuBarItemGeometry.excludingDividers(StatusItemScanner.scan())
            .filter { hidden.contains($0.windowID) && $0.frame.minX >= 0 }
    }

    /// Puts the cover up over the whole bar, painted with a capture of it.
    private func coverBar(_ band: CGRect, with image: CGImage) {
        cover.update(image, of: band)
        cover.show(over: band)
    }

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

    /// Covers just the section's strip, sampled with the items and Bouncer's own windows
    /// left out.
    private func coverSection(_ strip: CGRect, replicating revealed: [MenuBarItem]) async {
        let sample = await BackgroundCapture.sample(
            rect: strip, excluding: ownWindows(replicating: revealed))
        cover.update(sample, of: strip)
        cover.show(over: strip)
        bar.matchShade(to: sample)
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
        cover.hide()
        shield.hide()
        menuBar.setBoundaryMarkersVisible(true)
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
        cover.hide()
        shield.hide()
        menuBar.setBoundaryMarkersVisible(true)
        // Released last, so releasing it cannot re-arm a rehide for a section that is on its
        // way off screen anyway.
        menuBar.isRevealHeld = false
    }

    /// The full menu bar the items live on, in window-server coordinates.
    ///
    /// Anchored on an item rather than on `NSScreen.main`, which is the screen with keyboard
    /// focus: open the bar while working on a second display and the cover would go up over
    /// that screen's menu bar, leaving the items it is meant to hide in plain sight for as
    /// long as the bar is open.
    ///
    /// Height is the tallest item there is, not the first one's: items are not all the same
    /// height — 30 and 33 sit side by side in one bar — and a cover cut to a short one leaves
    /// the bottom of every taller icon showing. The gap between a screen and its visible
    /// frame is no better; it counts whatever else macOS reserves up there.
    ///
    /// The y is zero because the scanner only ever reports items at the top of the primary
    /// display.
    private func menuBarBand(around items: [MenuBarItem]) -> CGRect? {
        guard let onScreen = items.first(where: { $0.frame.minX >= 0 }),
              let height = items.map(\.frame.height).max(),
              let screen = NSScreen.screens.first(where: {
                  $0.frame.minX...$0.frame.maxX ~= onScreen.frame.midX
              })
        else { return nil }
        return CGRect(x: screen.frame.minX, y: 0, width: screen.frame.width, height: height)
    }

    /// The windows a capture of the menu bar has to leave out: the items being replicated,
    /// and Bouncer's own, which sit over the very strip being captured.
    private func ownWindows(replicating items: [MenuBarItem]) -> Set<UInt32> {
        var ids = Set(items.map(\.windowID))
        if let cover = cover.windowID { ids.insert(cover) }
        if let bar = bar.windowID { ids.insert(bar) }
        if let shield = shield.windowID { ids.insert(shield) }
        return ids
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
