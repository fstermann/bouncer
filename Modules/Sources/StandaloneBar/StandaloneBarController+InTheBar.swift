import AppKit
import BouncerFoundation
import MenuBar

extension StandaloneBarController {
    /// macOS 27's bar: the section is revealed into the menu bar and left there.
    ///
    /// Items there can only sit right of the notch, and those that do not fit go behind a chevron,
    /// which draws them left of the notch when opened. Widening the divider pushes half the section
    /// past what fits, so it lands on both sides, and a black band grows out of the notch behind it.
    /// Nothing is photographed or replicated: clicks go to the real items.
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
        if let sectionWidth {
            menuBar.sectionShift = NotchSplit.shift(for: sectionWidth, endingAt: end, notch: notch.range)
        }
        _ = await AgentItems.revealed(in: notch.range.upperBound...end, height: height)
        var frames = await settleBothSides(notch: notch.range)
        // The width is remembered from the last close, and unknown before the first: when the
        // section changed since, it is split again from where it landed.
        measureSection(frames, notch: notch.range, end: end)
        if let sectionWidth {
            let shift = NotchSplit.shift(for: sectionWidth, endingAt: end, notch: notch.range)
            if abs(shift - menuBar.sectionShift) > Self.resplitThreshold {
                menuBar.sectionShift = shift
                await AgentItems.change(from: frames)
                frames = await settleBothSides(notch: notch.range)
            }
        }
        let reach = NotchSplit.band(over: frames, notch: notch.range, end: end)
        await tab.show(at: tabFrame, reaching: reach, over: shape == nil ? slide : nil)
        finishOpening(of: [], from: [:], over: tabFrame)
    }

    /// Closes the chevron before collapsing: left open, every later reveal, a plain click on the icon
    /// included, draws the overflow over the app menus.
    func closeInTheBar(animated: Bool) async {
        if let end = menuBar.hiddenSectionEnd,
           let notch = Notch.on(displayOf: CGRect(x: end, y: 0, width: 1, height: 1)) {
            measureSection(await AgentItems.frames(), notch: notch.range, end: end)
        }
        AgentOverflow.close()
        menuBar.setVisibility(.collapsed)
        menuBar.setBoundaryMarkersVisible(true)
        await tab.hide(over: animated ? slide : nil)
    }

    /// Less than half an item: a smaller change in the shift moves nothing across the notch.
    private static let resplitThreshold: CGFloat = 16

    /// Opens the chevron, if the section overflowed, and returns every item once both sides have landed.
    private func settleBothSides(notch: ClosedRange<CGFloat>) async -> [CGRect] {
        if menuBar.sectionShift > 0 { await AgentOverflow.appearance() }
        AgentOverflow.open()
        return AgentOverflow.state == .open
            ? await AgentItems.overflowed(leftOf: notch.lowerBound)
            : await AgentItems.frames()
    }

    /// Reads how wide the revealed section is from `frames`, both sides of the notch together.
    private func measureSection(_ frames: [CGRect], notch: ClosedRange<CGFloat>, end: CGFloat) {
        let chevron = AgentOverflow.frame
        sectionWidth = NotchSplit.hiddenWidth(of: frames.filter { $0 != chevron }, notch: notch, end: end)
            ?? sectionWidth
    }
}
