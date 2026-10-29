import AppKit
import BouncerFoundation
import MenuBar

extension StandaloneBarController {
    /// macOS 27's open: reveal first, under a curtain, then read and photograph what came back.
    ///
    /// A hidden item there is neither drawn nor listed anywhere, so the section cannot be known
    /// before it is revealed, and the panel cannot be built where it will land. It can only land
    /// between the notch and the divider, so that stretch is curtained off first. Rearranging
    /// from the panel and centring under the notch are not built for this path yet.
    func openUnderCurtain(closingWhenLeft: Bool, animated: Bool) async {
        guard ClickForwarder.isPermitted else {
            Log.menuBar.error("Standalone bar: Accessibility not granted")
            return
        }
        guard let end = menuBar.hiddenSectionEnd,
              let notch = Notch.on(displayOf: CGRect(x: end, y: 0, width: 1, height: 1)),
              end > notch.range.upperBound,
              let height = NSScreen.main?.menuBarHeight
        else {
            let end = menuBar.hiddenSectionEnd.map { "\($0)" } ?? "unknown"
            Log.menuBar.error("Standalone bar: nowhere for the section to land, it ends at \(end, privacy: .public)")
            return
        }
        Log.menuBar.info("Standalone bar: opening under a curtain")
        slide = settings.preferences.animateBar ? settings.preferences.barAnimationDuration : nil
        closing.closesOnLeave = closingWhenLeft
        isUnderCurtain = true

        let reach = notch.range.upperBound...end
        let width = reach.upperBound - reach.lowerBound
        curtain.show(over: CGRect(x: reach.lowerBound, y: 0, width: width, height: height))
        menuBar.isRevealHeld = true
        menuBar.setBoundaryMarkersVisible(false)
        menuBar.setVisibility(.revealed)
        let found = await AgentItems.revealed(in: reach, height: height)
        let revealed = found.map(\.item)
        guard let strip = MenuBarItemGeometry.coverRect(for: revealed) else {
            Log.menuBar.info("Standalone bar: nothing is hidden")
            menuBar.setVisibility(.collapsed)
            menuBar.setBoundaryMarkersVisible(true)
            menuBar.isRevealHeld = false
            curtain.hide()
            isUnderCurtain = false
            return
        }
        await itemCapture.captureUnderCover(revealed)
        items = revealed
        revealedElements = found.map(\.element)
        let elements = Dictionary(found.map { ($0.item.windowID, $0.element) }) { first, _ in first }
        resolvingElements = Task { elements }

        cover.show(over: strip.insetBy(dx: -Self.coverBleed, dy: 0))
        bar.update(images: itemCapture.images)
        bar.show(revealed, below: strip)
        await Slide.panelOut(bar, cover, over: animated ? slide : nil)
        bar.setCrossing(false)
        curtain.hide()
        shield.show(over: strip)
        finishOpening(of: Set(revealed.map(\.windowID)), from: [:], over: strip)
    }
}
