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
        let duration = shape == nil ? slide : nil
        let layout = lastLayout?.end == end ? lastLayout : nil
        // The band goes out both ways at once, covering the items, which land behind it and show
        // together once both sides have settled. Uncovered, the right side lands well before the
        // overflow slides out on the left, and the app menus draw over the band until it has.
        var showing: Task<Void, Never>?
        if let layout {
            showing = Task { await tab.show(at: tabFrame, reaching: layout.reach, covered: true, over: duration) }
            if let duration { try? await Task.sleep(for: .seconds(duration * Self.revealDelay)) }
            tab.shade(layout.chevron.map { NotchSplit.shade(over: $0, notch: notch.range) })
        }
        reveal(shiftedFor: layout?.width, end: end, notch: notch.range)
        _ = await AgentItems.revealed(in: notch.range.upperBound...end, height: height)
        var frames = await settleBothSides(notch: notch.range)
        // Accessibility has the overflow's final frames well before it has finished sliding out.
        let overflowLanded = ContinuousClock.now + .seconds(AgentOverflow.slide)
        // Read here only before the first close: a reading taken while the bar still moves would
        // split it differently from one open to the next.
        if layout == nil, let width = sectionWidth(in: frames, notch: notch.range, end: end) {
            menuBar.sectionShift = NotchSplit.shift(for: width, endingAt: end, notch: notch.range)
            await AgentItems.change(from: frames)
            frames = await settleBothSides(notch: notch.range)
        }
        await showing?.value
        let reach = NotchSplit.band(over: frames, notch: notch.range, end: end)
        tab.shade(AgentOverflow.frame.map { NotchSplit.shade(over: $0, notch: notch.range) })
        if layout == nil {
            await tab.show(at: tabFrame, reaching: reach, over: duration)
        } else {
            tab.extend(to: reach, over: duration)
            if duration != nil { try? await Task.sleep(until: overflowLanded) }
            await tab.uncover(over: duration)
        }
        finishOpening(of: [], from: [:], over: tabFrame)
    }

    /// How long the items take to go once collapsed: the overflow back into the notch, the rest fading.
    private static let itemsLeave = 0.3

    /// How far into the band's slide the section is revealed: far enough that the items land on black.
    private static let revealDelay = 0.6

    private func reveal(shiftedFor width: CGFloat?, end: CGFloat, notch: ClosedRange<CGFloat>) {
        menuBar.isRevealHeld = true
        menuBar.setBoundaryMarkersVisible(false)
        menuBar.setVisibility(.revealed)
        if let width { menuBar.sectionShift = NotchSplit.shift(for: width, endingAt: end, notch: notch) }
    }

    /// Closes the chevron before collapsing: left open, every later reveal, a plain click on the icon
    /// included, draws the overflow over the app menus.
    func closeInTheBar(animated: Bool) async {
        if let end = menuBar.hiddenSectionEnd,
           let notch = Notch.on(displayOf: CGRect(x: end, y: 0, width: 1, height: 1)) {
            let frames = await AgentItems.frames()
            if let width = sectionWidth(in: frames, notch: notch.range, end: end) {
                let reach = NotchSplit.band(over: frames, notch: notch.range, end: end)
                lastLayout = NotchSplit.Layout(width: width, reach: reach, chevron: AgentOverflow.frame, end: end)
            }
        }
        // The reverse of opening: both sides fade out together and leave behind the cover, which
        // goes back into the notch once the app menus are back.
        let leaving = animated ? slide : nil
        tab.cover(over: leaving)
        if let leaving { try? await Task.sleep(for: .seconds(leaving)) }
        AgentOverflow.close()
        menuBar.setVisibility(.collapsed)
        menuBar.setBoundaryMarkersVisible(true)
        if leaving != nil { try? await Task.sleep(for: .seconds(Self.itemsLeave)) }
        tab.shade(nil)
        await tab.hide(over: animated ? slide : nil)
    }

    /// Opens the chevron, if the section overflowed, and returns every item once both sides have landed.
    private func settleBothSides(notch: ClosedRange<CGFloat>) async -> [CGRect] {
        if menuBar.sectionShift > 0 { await AgentOverflow.appearance() }
        AgentOverflow.open()
        return AgentOverflow.state == .open
            ? await AgentItems.overflowed(leftOf: notch.lowerBound)
            : await AgentItems.frames()
    }

    /// How wide the revealed section is in `frames`, both sides of the notch together.
    private func sectionWidth(in frames: [CGRect], notch: ClosedRange<CGFloat>, end: CGFloat) -> CGFloat? {
        let chevron = AgentOverflow.frame
        return NotchSplit.hiddenWidth(of: frames.filter { $0 != chevron }, notch: notch, end: end)
    }
}
