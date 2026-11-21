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
    func openInTheBar(closingWhenLeft: Bool, takingOver takeOver: TakeOver? = nil) async {
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
        let layout = lastLayout?.holds(endingAt: end, notch: notch.range) == true ? lastLayout : nil
        if let layout, !layout.overflows {
            return await openRightOfTheNotch(as: layout, at: tabFrame, takingOver: takeOver)
        }
        if let takeOver { await cover(for: takeOver, at: tabFrame, reaching: layout?.reach) }
        let duration = slide
        // The band goes out both ways at once, covering the items, which land behind it. The right
        // side shows as soon as it has landed; the left stays covered until the overflow has slid
        // out, or the app menus draw over the band until it has.
        var showing: Task<Void, Never>?
        if let layout, takeOver == nil {
            showing = Task { await tab.show(at: tabFrame, reaching: layout.reach, covered: true, over: duration) }
            if let duration { try? await Task.sleep(for: .seconds(duration * Self.revealDelay)) }
        }
        let revealed = reveal(shiftedFor: layout?.width, end: end, notch: notch.range)
        // The chevron's last place is shaded before it shows on the uncovered right.
        if let layout { tab.shade(over: layout.chevron, notch: notch.range) }
        let rightSide = layout.map { _ in Task { await showRightSide(after: showing, revealedAt: revealed, takeOver) } }
        if layout == nil { _ = await AgentItems.revealed(in: notch.range.upperBound...end, height: height) }
        let settled = await settleBothSides(notch: notch.range, expectingOverflow: layout != nil)
        var frames = settled.frames
        if layout == nil { frames = await splitIfOverflowing(frames, notch: notch.range, end: end) }
        await showing?.value
        let reach = NotchSplit.band(over: frames, notch: notch.range, end: end)
        tab.shade(over: AgentOverflow.frame, notch: notch.range)
        if layout == nil {
            await tab.show(at: tabFrame, reaching: reach, over: duration)
        } else {
            tab.extend(to: reach, over: duration)
            await showLeftSide(openedAt: settled.opened, notch: notch.range, end: end, over: duration)
            await rightSide?.value
        }
        finishOpeningInTheBar(over: tabFrame)
        Task { await rememberLayout(from: await AgentItems.settled()) }
    }

    /// Splits the section evenly around the notch on its first open, if it went behind the chevron, and
    /// returns where its items landed. Read here only before the first close: a reading taken while
    /// the bar still moves would split it differently from one open to the next.
    private func splitIfOverflowing(
        _ frames: [CGRect], notch: ClosedRange<CGFloat>, end: CGFloat
    ) async -> [CGRect] {
        guard await AgentOverflow.current() != .absent,
              let width = sectionWidth(in: frames, notch: notch, end: end)
        else { return frames }
        menuBar.sectionShift = NotchSplit.shift(for: width, endingAt: end, notch: notch)
        await AgentItems.change(from: frames)
        return await settleBothSides(notch: notch, expectingOverflow: true).frames
    }

    /// Opens a section that fits right of the notch: revealed where it is, with no chevron to wait
    /// for, so the band goes out at once to where it reached last time and the items fade in on it
    /// as macOS draws them, which it starts some 160 ms after the reveal. Then fitted to them.
    private func openRightOfTheNotch(
        as layout: NotchSplit.Layout, at tabFrame: CGRect, takingOver takeOver: TakeOver?
    ) async {
        let reach = layout.reach
        if let takeOver { await cover(for: takeOver, at: tabFrame, reaching: reach) }
        let revealed = reveal(shiftedFor: nil, end: layout.end, notch: layout.notch)
        if takeOver != nil {
            try? await Task.sleep(until: revealed + .seconds(Self.rightSideLands))
            takeOver?.letGo()
            async let left: Void = tab.uncover(.left, over: slide)
            await tab.uncover(.right, over: slide)
            await left
        } else {
            await tab.show(at: tabFrame, reaching: reach, over: slide)
        }
        tab.shade(over: nil, notch: layout.notch)
        finishOpeningInTheBar(over: tabFrame)
        Task { await fitOrOpenTheOverflow(notch: layout.notch) }
    }

    /// Fits the band to the items once they hold still. The section may have grown since it was
    /// measured, an app having added items, and gone behind the chevron: then the chevron is opened,
    /// and the next open measures it again.
    private func fitOrOpenTheOverflow(notch: ClosedRange<CGFloat>) async {
        guard await AgentOverflow.current() != .absent else {
            let frames = await AgentItems.settled()
            fitBand(to: frames)
            return await rememberLayout(from: frames)
        }
        guard isOpen else { return }
        lastLayout = nil
        let settled = await settleBothSides(notch: notch, expectingOverflow: true)
        fitBand(to: settled.frames)
        try? await Task.sleep(until: settled.opened + .seconds(AgentOverflow.slide))
        let frames = await AgentItems.frames()
        fitBand(to: frames)
        await rememberLayout(from: frames)
    }

    /// Keeps how the section lies for the next open. Read while the bar is open rather than as it
    /// closes: MenuBarAgent can take some 400 ms to answer, and the close would wait on it. Only
    /// with the chevron open or with none: closed, it holds just the right side.
    private func rememberLayout(from frames: [CGRect]) async {
        let overflow = await AgentOverflow.current()
        let chevron = await Task.detached { AgentOverflow.frame }.value
        guard isOpen, overflow != .closed, let end = menuBar.hiddenSectionEnd,
              let notch = Notch.on(displayOf: CGRect(x: end, y: 0, width: 1, height: 1)),
              let width = NotchSplit.hiddenWidth(of: frames.filter { $0 != chevron }, notch: notch.range, end: end)
        else { return }
        lastLayout = NotchSplit.Layout(
            width: width, reach: NotchSplit.band(over: frames, notch: notch.range, end: end), chevron: chevron,
            overflows: overflow == .open, end: end, notch: notch.range
        )
    }

    private func finishOpeningInTheBar(over tabFrame: CGRect) {
        finishOpening(of: [], from: [:], over: tabFrame)
        closeWhenTheOverflowCloses()
        refitWhenAppsComeAndGo()
    }

    /// Puts the band up covered and unseen, and has a todo page take its shape over it. With nothing
    /// measured yet, the page goes into the notch, and is let go at once.
    private func cover(for takeOver: TakeOver, at tabFrame: CGRect, reaching reach: ClosedRange<CGFloat>?) async {
        let band = NotchTab.frame(under: reach ?? tabFrame.minX...tabFrame.maxX, barHeight: tabFrame.height)
        tab.isConcealed = true
        if let reach { await tab.show(at: tabFrame, reaching: reach, covered: true, over: nil) }
        await takeOver.shape(BarWindow.appKitFrame(for: band))
        tab.isConcealed = false
        if reach == nil { takeOver.letGo() }
    }

    /// Uncovers the right side once the band is out and the side has landed. It lands from some 30 ms
    /// after the reveal, an item at a time, and Accessibility stalls for some 300 ms after it, so it
    /// is given a fixed while rather than read.
    ///
    /// A page turning into the band fades off it only then: the reveal has the menu bar drawn over the
    /// band for a frame, which the page hides as long as it is up.
    private func showRightSide(
        after showing: Task<Void, Never>?, revealedAt revealed: ContinuousClock.Instant, _ takeOver: TakeOver?
    ) async {
        await showing?.value
        try? await Task.sleep(until: revealed + .seconds(Self.rightSideLands))
        takeOver?.letGo()
        await tab.uncover(.right, over: slide)
    }

    /// Uncovers the left side once the overflow has slid out: until then the app menus still draw
    /// over the band there, and fading the cover any sooner shows them through it.
    private func showLeftSide(
        openedAt opened: ContinuousClock.Instant, notch: ClosedRange<CGFloat>, end: CGFloat,
        over duration: TimeInterval?
    ) async {
        try? await Task.sleep(until: opened + .seconds(AgentOverflow.slide))
        // Read again once the overflow is out: a batch can still arrive after it looked settled.
        let landed = await AgentItems.frames()
        tab.extend(to: NotchSplit.band(over: landed, notch: notch, end: end), over: duration)
        await tab.uncover(.left, over: duration)
    }

    /// Keeps the band's right end past the section's last item through a Cmd-drag, as items dragged
    /// in or out move the divider. Accessibility stalls for the whole drag, so the divider is all
    /// there is; the release fits the band exactly.
    func followDragInTheBar() {
        guard menuBar.onHiddenDividerMove == nil else { return }
        menuBar.onHiddenDividerMove = { [weak self] in
            guard let self, isOpen, isInTheBar, let start = menuBar.hiddenDividerStart else { return }
            tab.extend(rightTo: NotchSplit.bandEnd(dividerStart: start), over: slide)
        }
    }

    /// Fits the band to the section again once the bar has settled after a release: an item dragged
    /// in or out changes how far the section reaches, and macOS says nothing when it lands.
    func refitInTheBar() async {
        menuBar.onHiddenDividerMove = nil
        let frames = await AgentItems.settled()
        fitBand(to: frames)
        await rememberLayout(from: frames)
    }

    private func fitBand(to frames: [CGRect]) {
        guard isOpen, isInTheBar, let end = menuBar.hiddenSectionEnd,
              let notch = Notch.on(displayOf: CGRect(x: end, y: 0, width: 1, height: 1))
        else { return }
        tab.extend(to: NotchSplit.band(over: frames, notch: notch.range, end: end), over: slide)
        tab.shade(over: AgentOverflow.frame, notch: notch.range)
    }

    /// Another app coming to the front closes the chevron, taking the left side back into the notch
    /// and leaving the band over the app menus, so the bar goes with it.
    private func closeWhenTheOverflowCloses() {
        appSwitches = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            // Bouncer comes to the front itself for the page menu, which closes nothing.
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let isBouncer = app?.processIdentifier == ProcessInfo.processInfo.processIdentifier
            MainActor.assumeIsolated {
                guard let self, self.isOpen, !isBouncer, AgentOverflow.state != .open else { return }
                Task { await self.close() }
            }
        }
    }

    /// An app launching or quitting adds or takes away its items, landing them outside the band.
    /// Watched through the list of apps: most with items are agents, which the launch
    /// notification leaves out.
    private func refitWhenAppsComeAndGo() {
        appsChange = NSWorkspace.shared.observe(\.runningApplications) { [weak self] _, _ in
            Task { @MainActor in await self?.refitAfterItemsChange() }
        }
    }

    /// An app makes its items around when it is listed, so the band fits what is there at once, as
    /// soon as anything moves after, and once that has settled.
    private func refitAfterItemsChange() async {
        let now = await AgentItems.frames()
        fitBand(to: now)
        await AgentItems.change(from: now, within: Self.itemsArrive)
        fitBand(to: await AgentItems.frames())
        let frames = await AgentItems.settled()
        fitBand(to: frames)
        await rememberLayout(from: frames)
    }

    /// How long after an app is listed its items may still land.
    private static let itemsArrive: Duration = .seconds(2)

    /// How long macOS takes to take the items away once collapsed, measured at 235 to 530 ms.
    private static let itemsLeave = 0.55
    /// How long the items fade under the cover, through most of the time macOS takes, so they go in
    /// one fade rather than vanishing ahead of a band left empty.
    private static let itemsFade = 0.45

    /// How long after the reveal the right side has landed, its last item measured some 150 ms in.
    private static let rightSideLands = 0.2

    /// How far into the band's slide the section is revealed: far enough that the cover is past the items.
    private static let revealDelay = 0.4

    /// Returns when it was revealed.
    private func reveal(
        shiftedFor width: CGFloat?, end: CGFloat, notch: ClosedRange<CGFloat>
    ) -> ContinuousClock.Instant {
        menuBar.isRevealHeld = true
        menuBar.setBoundaryMarkersVisible(false)
        menuBar.setVisibility(.revealed)
        if let width { menuBar.sectionShift = NotchSplit.shift(for: width, endingAt: end, notch: notch) }
        return .now
    }

    /// Closes the chevron before collapsing: left open, every later reveal, a plain click on the icon
    /// included, draws the overflow over the app menus.
    func closeInTheBar(animated: Bool, into page: PageOpening?) async {
        menuBar.onHiddenDividerMove = nil
        appSwitches.map(NSWorkspace.shared.notificationCenter.removeObserver)
        appSwitches = nil
        appsChange = nil
        // The reverse of opening: the items fade out under the cover while macOS takes them away,
        // then the band goes back into the notch.
        tab.cover(over: animated ? Self.itemsFade : nil)
        // Only where there is one: looking finds MenuBarAgent busy as often as not, and the
        // collapse would wait on it.
        if lastLayout?.overflows != false { await Task.detached { AgentOverflow.close() }.value }
        menuBar.setVisibility(.collapsed)
        menuBar.setBoundaryMarkersVisible(true)
        // Waited even unanimated: a todo page taking over covers the items only until it grows.
        let left = ContinuousClock.now + .seconds(Self.itemsLeave)
        let goes: @MainActor () async -> Void = { [self] in
            try? await Task.sleep(until: left)
            tab.shade(nil)
            await tab.hide(over: animated && page == nil ? slide : nil)
        }
        if let page { await page(goes) } else { await goes() }
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
        // Off the main thread: MenuBarAgent answers nothing for some 300 ms after a reveal, and the
        // right side's uncovering must not wait behind it.
        let state = await Task.detached { AgentOverflow.open(); return AgentOverflow.state }.value
        let frames = state == .open
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
