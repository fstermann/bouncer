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

    private let menuBar: MenuBarManager
    private let itemCapture = ItemCapture()
    private let background = BackgroundCapture()
    private let cover = CoverWindow()
    private let bar = ReplicaBar()

    private var itemObservation: ObservationLoop?
    private var backgroundObservation: ObservationLoop?
    /// The items being replicated, held so a click can be mapped back to a real one.
    private var items: [MenuBarItem] = []

    public init(menuBar: MenuBarManager) {
        self.menuBar = menuBar
        bar.onClick = { [weak self] _, point, rightButton, modifiers in
            self?.forward(to: point, rightButton: rightButton, modifiers: modifiers)
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
        let hidden = Set(
            MenuBarItemGeometry.offScreen(
                MenuBarItemGeometry.excludingDividers(StatusItemScanner.scan()),
                screens: screens
            ).map(\.windowID)
        )
        guard !hidden.isEmpty else {
            Log.menuBar.info("Standalone bar: nothing is hidden — is the section already revealed?")
            return
        }

        // Reveal: the items have no frames worth reading and no pixels at all while they
        // are off the display, so everything below depends on them being back.
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

        // The cover goes up from a single capture rather than waiting for the stream's
        // first frame, because until it is up the user is looking at the items we just
        // revealed. One capture costs about 11 ms; the stream takes several times that to
        // start, and that difference is the flash.
        cover.show(over: strip)
        cover.update(await BackgroundCapture.sample(rect: strip, excluding: revealed))

        bar.show(revealed, below: strip)
        await itemCapture.begin(revealed)
        bar.update(images: itemCapture.images)

        itemObservation = ObservationLoop { [weak self] in
            guard let self else { return }
            self.bar.update(images: self.itemCapture.images)
        }
        backgroundObservation = ObservationLoop { [weak self] in
            guard let self else { return }
            self.cover.update(self.background.image)
        }
        await background.start(rect: strip, excluding: revealed)

        isOpen = true
        let width = Int(strip.width)
        Log.menuBar.info(
            "Standalone bar: open, \(revealed.count, privacy: .public) items over \(width, privacy: .public) pt")
    }

    /// Puts everything away and hands hiding back to the divider.
    public func close() async {
        guard isOpen else { return }
        isOpen = false

        itemObservation?.cancel()
        itemObservation = nil
        backgroundObservation?.cancel()
        backgroundObservation = nil

        bar.hide()
        cover.hide()
        items = []

        await itemCapture.stop()
        await background.stop()
        menuBar.setVisibility(.collapsed)
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

    private func forward(to point: CGPoint, rightButton: Bool, modifiers: CGEventFlags) {
        guard ClickForwarder.isPermitted else {
            Log.menuBar.error("Standalone bar: click ignored, Accessibility not granted")
            return
        }
        ClickForwarder.click(at: point, rightButton: rightButton, modifiers: modifiers)
    }
}
