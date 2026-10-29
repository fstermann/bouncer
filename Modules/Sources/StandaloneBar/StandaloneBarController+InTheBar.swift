import AppKit
import BouncerFoundation
import MenuBar

extension StandaloneBarController {
    /// macOS 27's bar: the section is revealed into the menu bar and left there.
    ///
    /// Items there can only sit right of the notch, and those that do not fit go behind a chevron,
    /// which draws them left of the notch when opened. Both sides slide out of the notch on their
    /// own, so nothing is photographed or replicated: the bar is the reveal, the open chevron and
    /// the todo tab under the notch. Clicks go to the real items.
    func openInTheBar(closingWhenLeft: Bool, takingShape shape: (@MainActor (CGRect) async -> Void)? = nil) async {
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
        Log.menuBar.info("Standalone bar: opening in the bar")
        slide = settings.preferences.animateBar ? settings.preferences.barAnimationDuration : nil
        closing.closesOnLeave = closingWhenLeft
        isInTheBar = true

        let tabFrame = NotchTab.frame(under: notch.range, barHeight: height)
        if let shape { await shape(BarWindow.appKitFrame(for: tabFrame)) }
        menuBar.isRevealHeld = true
        menuBar.setBoundaryMarkersVisible(false)
        menuBar.setVisibility(.revealed)
        // The chevron appears once the section has landed, and only if some of it did not fit.
        _ = await AgentItems.revealed(in: notch.range.upperBound...end, height: height)
        AgentOverflow.open()
        await tab.show(at: tabFrame, over: shape == nil ? slide : nil)
        finishOpening(of: [], from: [:], over: tabFrame)
    }

    /// Closes the chevron before collapsing: left open, every later reveal, a plain click on the icon
    /// included, draws the overflow over the app menus.
    func closeInTheBar(animated: Bool) async {
        AgentOverflow.close()
        menuBar.setVisibility(.collapsed)
        menuBar.setBoundaryMarkersVisible(true)
        await tab.hide(over: animated ? slide : nil)
    }
}
