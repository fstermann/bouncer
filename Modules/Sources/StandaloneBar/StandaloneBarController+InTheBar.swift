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
        // The band goes out both ways at once, covering the items, which land behind it. The right
        // side shows as soon as it has landed; the left stays covered until the overflow has slid
        // out, or the app menus draw over the band until it has.
        var showing: Task<Void, Never>?
        if let layout {
            showing = Task { await tab.show(at: tabFrame, reaching: layout.reach, covered: true, over: duration) }
            if let duration { try? await Task.sleep(for: .seconds(duration * Self.revealDelay)) }
        }
        reveal(shiftedFor: layout?.width, end: end, notch: notch.range)
        // The chevron's last place is shaded before it shows on the uncovered right.
        if let layout { tab.shade(layout.chevron.map { NotchSplit.shade(over: $0, notch: notch.range) }) }
        // The right side lands some 30 ms after the reveal, before the band has finished growing.
        // Accessibility stalls for some 300 ms after it, so waiting to read it there would show it late.
        let rightSide = layout.map { _ in Task { await showing?.value; await tab.uncover(.right, over: duration) } }
        if layout == nil { _ = await AgentItems.revealed(in: notch.range.upperBound...end, height: height) }
        let settled = await settleBothSides(notch: notch.range, expectingOverflow: layout != nil)
        var frames = settled.frames
        // Read here only before the first close: a reading taken while the bar still moves would
        // split it differently from one open to the next.
        if layout == nil, let width = sectionWidth(in: frames, notch: notch.range, end: end) {
            menuBar.sectionShift = NotchSplit.shift(for: width, endingAt: end, notch: notch.range)
            await AgentItems.change(from: frames)
            frames = await settleBothSides(notch: notch.range, expectingOverflow: true).frames
        }
        await showing?.value
        let reach = NotchSplit.band(over: frames, notch: notch.range, end: end)
        tab.shade(AgentOverflow.frame.map { NotchSplit.shade(over: $0, notch: notch.range) })
        if layout == nil {
            await tab.show(at: tabFrame, reaching: reach, over: duration)
        } else {
            tab.extend(to: reach, over: duration)
            await showLeftSide(openedAt: settled.opened, notch: notch.range, end: end, over: duration)
            await rightSide?.value
        }
        finishOpening(of: [], from: [:], over: tabFrame)
        closeWhenTheOverflowCloses()
    }

    /// Uncovers the left side over the overflow's last stretch of sliding out: Accessibility has its
    /// final frames well before then.
    private func showLeftSide(
        openedAt opened: ContinuousClock.Instant, notch: ClosedRange<CGFloat>, end: CGFloat,
        over duration: TimeInterval?
    ) async {
        var uncovering: Task<Void, Never>?
        if let duration {
            try? await Task.sleep(until: opened + .seconds(AgentOverflow.slide - duration))
            uncovering = Task { await tab.uncover(.left, over: duration) }
            try? await Task.sleep(until: opened + .seconds(AgentOverflow.slide))
        }
        // Read again once the overflow is out: a batch can still arrive after it looked settled.
        let landed = await AgentItems.frames()
        tab.extend(to: NotchSplit.band(over: landed, notch: notch, end: end), over: duration)
        if let uncovering { await uncovering.value } else { await tab.uncover(.left, over: nil) }
    }

    /// Another app coming to the front closes the chevron, taking the left side back into the notch
    /// and leaving the band over the app menus, so the bar goes with it.
    private func closeWhenTheOverflowCloses() {
        appSwitches = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isOpen, AgentOverflow.state != .open else { return }
                Task { await self.close() }
            }
        }
    }

    /// How long the items take to go once collapsed: the overflow back into the notch, the rest fading.
    private static let itemsLeave = 0.3

    /// How far into the band's slide the section is revealed: far enough that the cover is past the items.
    private static let revealDelay = 0.4

    private func reveal(shiftedFor width: CGFloat?, end: CGFloat, notch: ClosedRange<CGFloat>) {
        menuBar.isRevealHeld = true
        menuBar.setBoundaryMarkersVisible(false)
        menuBar.setVisibility(.revealed)
        if let width { menuBar.sectionShift = NotchSplit.shift(for: width, endingAt: end, notch: notch) }
    }

    /// Closes the chevron before collapsing: left open, every later reveal, a plain click on the icon
    /// included, draws the overflow over the app menus.
    func closeInTheBar(animated: Bool) async {
        appSwitches.map(NSWorkspace.shared.notificationCenter.removeObserver)
        appSwitches = nil
        // Measured only with the chevron open: closed, it holds just the right side.
        if AgentOverflow.state == .open,
           let end = menuBar.hiddenSectionEnd,
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

    /// Opens the chevron, if the section overflowed, and returns every item once both sides have
    /// landed, with when it was opened.
    ///
    /// - Parameter expectingOverflow: whether to wait for the chevron. A split section always
    ///   overflows, the shift or not: one wider than both sides gets none.
    private func settleBothSides(
        notch: ClosedRange<CGFloat>, expectingOverflow: Bool
    ) async -> (frames: [CGRect], opened: ContinuousClock.Instant) {
        if expectingOverflow { await AgentOverflow.appearance() }
        let opened = ContinuousClock.now
        AgentOverflow.open()
        let frames = AgentOverflow.state == .open
            ? await AgentItems.overflowed(leftOf: notch.lowerBound)
            : await AgentItems.frames()
        return (frames, opened)
    }

    /// How wide the revealed section is in `frames`, both sides of the notch together.
    private func sectionWidth(in frames: [CGRect], notch: ClosedRange<CGFloat>, end: CGFloat) -> CGFloat? {
        let chevron = AgentOverflow.frame
        return NotchSplit.hiddenWidth(of: frames.filter { $0 != chevron }, notch: notch, end: end)
    }
}
