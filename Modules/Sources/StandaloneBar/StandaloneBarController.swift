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

    public func toggle() async {
        isOpen ? await close() : await open()
    }

    /// Reveals the hidden section, hides it again behind a cover, and replicates it below.
    public func open() async {
        guard !isOpen else { return }
        guard CGPreflightScreenCaptureAccess() else {
            Log.menuBar.error("Standalone bar: Screen Recording not granted")
            return
        }
        Log.menuBar.info("Standalone bar: opening")

        // Which items are hidden has to be settled *before* revealing them, because once
        // they are back on screen they are indistinguishable from the ones that were
        // visible all along. Identity survives the move; position does not.
        let screens = NSScreen.screens.map(\.frame)
        let all = MenuBarItemGeometry.excludingDividers(StatusItemScanner.scan())
        let hidden = Set(MenuBarItemGeometry.offScreen(all, screens: screens).map(\.windowID))
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
        // The whole bar rather than the section, for as long as it is open. The stream that
        // paints this renders the bar with the replicated items left out, so a cover the width
        // of the bar hides exactly them and shows everything else live.
        let band = menuBarBand(around: all)
        var bandImage: CGImage?
        if let band {
            bandImage = await BackgroundCapture.sample(rect: band, excluding: [], in: content)
            cover.update(bandImage, of: band)
            cover.show(over: band)
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

        // Reveal: the items have no frames worth reading and no pixels at all while they
        // are off the display, so everything below depends on them being back. The boundary
        // marker goes with them: it points at where hiding ends in a bar the user is not
        // being shown.
        menuBar.setBoundaryMarkersVisible(false)
        menuBar.setVisibility(.revealed)
        await waitForPlacement(of: hidden)

        let revealed = MenuBarItemGeometry.excludingDividers(StatusItemScanner.scan())
            .filter { hidden.contains($0.windowID) && $0.frame.minX >= 0 }
        guard let strip = MenuBarItemGeometry.coverRect(for: revealed) else {
            Log.menuBar.info("Standalone bar: the hidden section did not come back on screen")
            menuBar.setVisibility(.collapsed)
            return
        }
        items = revealed

        let beforeCapture = frames(of: hidden)
        await itemCapture.begin(revealed, in: content)

        // Shown as soon as there are pictures to show, at the positions the items hold now.
        // Capturing can put a recording indicator in the bar, and anything arriving in the bar
        // pushes every item along, so these positions are not guaranteed to last. Waiting that
        // out before showing anything cost more than half the open; `followTheShift` moves the
        // bar afterwards on the occasions it is needed.
        bar.update(images: itemCapture.images)
        bar.matchShade(to: bandImage)
        bar.show(revealed, below: strip)

        // Without a band there is nothing to cover the whole bar with, so the section itself
        // is covered — the only option on a bar with no visible item to anchor on.
        let covered = band ?? strip
        if band == nil {
            let sample = await BackgroundCapture.sample(
                rect: covered, excluding: ownWindows(replicating: revealed))
            cover.update(sample, of: covered)
            cover.show(over: covered)
            bar.matchShade(to: sample)
        }

        isOpen = true
        watchForThePointerLeaving()
        settling = Task { [weak self] in
            await self?.followTheShift(of: hidden, from: beforeCapture)
        }
        let width = Int(strip.width)
        Log.menuBar.info(
            "Standalone bar: open, \(revealed.count, privacy: .public) items over \(width, privacy: .public) pt")
    }

    /// Moves the bar to wherever the recording indicator pushed the items.
    ///
    /// A replica has to sit under the item it stands for: the menu comes out of the real
    /// item, not its picture, so a bar left where the items *were* sends the user to click an
    /// icon whose menu opens somewhere else. This is the one shift there is to follow — it
    /// ends when the indicator has landed, and nothing is left running after it.
    private func followTheShift(of ids: Set<UInt32>, from before: [UInt32: CGRect]) async {
        await waitForStillness(of: ids, movedFrom: before)
        guard !Task.isCancelled, isOpen else { return }

        let settled = MenuBarItemGeometry.excludingDividers(StatusItemScanner.scan())
            .filter { ids.contains($0.windowID) && $0.frame.minX >= 0 }
        guard let strip = MenuBarItemGeometry.coverRect(for: settled),
              settled.map(\.frame) != items.map(\.frame)
        else { return }

        items = settled
        bar.show(settled, below: strip)
    }

    /// Puts everything away and hands hiding back to the divider.
    public func close() async {
        guard isOpen else { return }
        isOpen = false

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
        await waitForRemoval(of: replicated)
        cover.hide()
        menuBar.setBoundaryMarkersVisible(true)
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

    /// Waits for the window server to place the items the divider just released.
    ///
    /// Collapsing the divider does not move anything synchronously, and frames read before
    /// the move lands are the old off-screen ones — which puts the cover and the bar in
    /// the wrong place, visibly. Yielding once is not enough; the move takes a few frames.
    ///
    /// This is a bounded wait inside an interaction the user just asked for, not a poll: it
    /// returns the moment the frames arrive, and nothing runs outside an open.
    private func waitForPlacement(of ids: Set<UInt32>) async {
        for _ in 0..<30 {
            let placed = StatusItemScanner.scan()
                .filter { ids.contains($0.windowID) && $0.frame.minX >= 0 }
            if placed.count == ids.count { return }
            try? await Task.sleep(for: .milliseconds(8))
        }
        Log.menuBar.error("Standalone bar: revealed items never landed on screen")
    }

    /// Waits for the divider to push the items back off the display.
    ///
    /// The mirror of `waitForPlacement`: collapsing does not move anything synchronously
    /// either, and the cover has to stay up until it has.
    private func waitForRemoval(of ids: Set<UInt32>) async {
        for _ in 0..<30 {
            let onScreen = StatusItemScanner.scan()
                .filter { ids.contains($0.windowID) && $0.frame.minX >= 0 }
            if onScreen.isEmpty { return }
            try? await Task.sleep(for: .milliseconds(8))
        }
        Log.menuBar.error("Standalone bar: the section never went back off screen")
    }

    /// The frames of `ids`, as the window server currently reports them.
    private func frames(of ids: Set<UInt32>) -> [UInt32: CGRect] {
        Dictionary(
            StatusItemScanner.scan()
                .filter { ids.contains($0.windowID) }
                .map { ($0.windowID, $0.frame) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Waits until the items have held still for a while, or gives up.
    ///
    /// The recording indicator does not arrive with the first captured frame — it takes a
    /// few hundred milliseconds, and shifts the whole bar when it lands. Two readings in a
    /// row agreeing proves nothing at that distance, so stillness has to be held.
    ///
    /// The hold is short, and the wait ends early once the shift has come and gone: what is
    /// being waited for is a single event, so a run of agreeing readings after it has landed
    /// is the answer, not evidence towards it. `movedFrom` is where the items sat before the
    /// capture, which is what makes the shift recognisable rather than merely absent.
    ///
    /// Bounded, and inside an open the user asked for.
    private func waitForStillness(of ids: Set<UInt32>, movedFrom before: [UInt32: CGRect]) async {
        var previous = before
        var still = 0
        var hasMoved = false
        for reading in 0..<Self.stillnessLimit {
            // Nothing has stirred in the time the indicator takes to land, so nothing is
            // going to: it was already in the bar before this open, and shifted it then.
            if !hasMoved, reading >= Self.shiftDeadline { return }

            try? await Task.sleep(for: .milliseconds(16))
            let current = frames(of: ids)
            still = current == previous ? still + 1 : 0
            hasMoved = hasMoved || current != before
            previous = current
            if hasMoved, still >= Self.stillnessRequired { return }
        }
    }

    /// Readings that must agree in a row once the bar has shifted, how long a shift is waited
    /// for before concluding there will not be one, and the most that will be waited for
    /// either way — about a tenth, a quarter and half a second.
    private static let stillnessRequired = 6
    private static let shiftDeadline = 16
    private static let stillnessLimit = 30

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
