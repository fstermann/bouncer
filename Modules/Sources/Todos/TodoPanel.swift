import AppKit
import BouncerFoundation
import MenuBar
import SwiftUI

/// The todo page's window: a black panel that grows out of the notch, or out of a notch-sized
/// point at the top centre of a display without one, the way the notch-style bar does. Switching
/// pages, it grows out of the items panel instead, and goes back into it.
///
/// It opens key, without activating Bouncer, so a todo can be typed straight away. It goes when
/// the user clicks elsewhere or presses Escape, and when the pointer leaves: after a grace period,
/// or at once once it is well clear. The panel changes shape under a still pointer, and a pointer
/// left just outside it has not left.
/// Springs the todo panel into a frame, in AppKit screen coordinates, and returns once it is there.
public typealias Shaping = @MainActor (CGRect) async -> Void

@MainActor
final class TodoPanel {
    /// The pointer left for good, or the user clicked elsewhere.
    var onDismiss: (@MainActor () -> Void)?
    var onEscape: (@MainActor () -> Void)?
    /// Command-F.
    var onFind: (@MainActor () -> Void)?
    /// Whether the pointer leaving may close the panel: not while something is being typed into it.
    var mayCloseOnLeave: (@MainActor () -> Bool)?
    /// A click landed outside the open menu; returns whether it closed the menu and so is spent.
    var onClickOutsideMenu: (@MainActor () -> Bool)?

    private var window: TodoWindow?
    private var surface: SurfaceView?
    private var content: NSHostingView<TodoPageView>?
    private var menuHost: NSHostingView<RowMenuHost>?
    private var resignObserver: NSObjectProtocol?
    /// Where the panel rests, and the notch it grows from, in AppKit screen coordinates.
    private var rest: CGRect = .zero
    private var notch: (rect: CGRect, isReal: Bool) = (.zero, true)
    /// Where a row's open menu hangs, in AppKit screen coordinates, past the panel's edge if need be.
    private var menu: CGRect?
    /// Set while the surface is springing, which a refit must not cut short.
    private var isMoving = false
    /// Installed only while the pointer is outside the panel, between leaving and coming back.
    private var leaveMonitors: [Any] = []
    private var leaveGrace: Task<Void, Never>?

    private static let grace: Duration = .milliseconds(1500)
    /// How far outside the panel the pointer can stray before it has plainly left.
    private static let reach: CGFloat = 80

    static let cornerRadius: CGFloat = 12
    /// Transparent margin around the panel, so the spring's overshoot is drawn rather than clipped.
    private static let room = CGSize(width: 12, height: 4)

    private static var pointerScreen: NSScreen? {
        NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
    }

    /// - Parameters:
    ///   - screen: whose notch to grow out of, the one under the pointer when `nil`.
    ///   - start: what to grow out of instead of the notch, in screen coordinates.
    func open(
        _ page: TodoPage, on screen: NSScreen?, over duration: TimeInterval?, from start: CGRect?,
        onceCovered: () async -> Void
    ) async {
        let screen = screen ?? Self.pointerScreen
        guard window == nil, let screen else { return }
        let range = DisplayNotch.range(
            left: screen.auxiliaryTopLeftArea, right: screen.auxiliaryTopRightArea, screen: screen.frame
        )
        let top = screen.frame.maxY
        notch = (CGRect(
            x: range.range.lowerBound, y: top - screen.menuBarHeight,
            width: range.range.upperBound - range.range.lowerBound, height: screen.menuBarHeight
        ), range.isReal)
        page.menuBarHeight = screen.menuBarHeight
        rest = CGRect(
            x: notch.rect.midX - TodoPage.width / 2, y: top - page.height, width: TodoPage.width, height: page.height
        )
        let window = make(page)
        guard let surface, let content else { return }
        // Laid out now, so the page has measured itself before it starts to grow.
        content.layoutSubtreeIfNeeded()
        let origin = start ?? notch.rect
        reach(origin, in: window)
        window.orderFrontRegardless()
        window.makeKey()
        page.focusRequests += 1
        guard let duration else {
            await onceCovered()
            return settle(window)
        }
        isMoving = true
        content.alphaValue = 0
        // The content is pinned to the surface's top centre, so the surface reveals it as it grows.
        shape(surface, to: local(origin, in: window))
        if start != nil {
            // Fades in over the panel it replaces, which is only taken away once it is covered.
            let appear = Motion(duration: duration * 0.6, bounce: 0)
            for view in body(surface) {
                view.alphaValue = 0
                appear.fade(view, to: 1)
            }
            await appear.finished()
            await onceCovered()
        } else if !notch.isReal {
            body(surface).forEach { $0.alphaValue = 0 }
        }
        // The same springs as the items page, so the two pages grow and focus alike.
        let grow = Motion(duration: duration * 2.4, bounce: 0.1)
        shape(surface, to: local(rest, in: window), on: grow)
        if start == nil, !notch.isReal { body(surface).forEach { grow.fade($0, to: 1) } }
        Motion(duration: duration * 1.6, bounce: 0, delay: duration * 0.6, startingWith: grow).focusIn([content])
        await grow.finished()
        isMoving = false
        guard window === self.window else { return }
        Motion.unfocus([content])
        settle(window)
    }

    /// Lets go of the window at once, so an open started while this one is still going away
    /// builds a window of its own rather than one this close is about to take down.
    ///
    /// - Parameter items: brings up the panel this one goes into instead of the notch, and is handed
    ///   `shape` to call with that panel's frame once its windows are up: this panel springs into
    ///   that frame, and `shape` returns once it has. Left uncalled, this panel goes into the notch.
    func close(over duration: TimeInterval?, into items: ((@escaping Shaping) async -> Void)?) async {
        guard let window, let surface else { return }
        stopObserving()
        let content = content
        let rest = rest, notch = notch
        self.window = nil
        self.surface = nil
        self.content = nil
        menuHost = nil
        menu = nil
        isMoving = false
        if let duration, let content { Motion(duration: duration * 0.6, bounce: 0).focusOut([content]) }
        var isShaped = false
        await items? { [self] frame in
            isShaped = true
            guard let duration else { return }
            reach(frame, in: window, resting: rest)
            let gather = Motion(duration: duration * 1.6, bounce: 0)
            shape(surface, to: local(frame, in: window), on: gather)
            await gather.finished()
        }
        guard let duration else { return window.orderOut(nil) }
        if isShaped {
            // Shaped like the panel underneath by now, and faded off it rather than lifted.
            let fade = Motion(duration: duration * 0.6, bounce: 0)
            fade.fade(window.contentView, to: 0)
            await fade.finished()
        } else {
            reach(notch.rect, in: window, resting: rest)
            let gather = Motion(duration: duration * 1.6, bounce: 0)
            shape(surface, to: local(notch.rect, in: window), on: gather)
            if !notch.isReal { body(surface).forEach { gather.fade($0, to: 0) } }
            await gather.finished()
        }
        window.orderOut(nil)
    }

    /// Fits the panel to the page's height, keeping its top against the top of the display.
    func fit(_ page: TodoPage) {
        guard let window else { return }
        let previous = rest
        rest = CGRect(x: rest.minX, y: rest.maxY - page.height, width: rest.width, height: page.height)
        menu = page.menu.map { $0.frame(size: page.menuSize, under: page.menuIcon, in: rest) }
        guard !isMoving else { return }
        if rest.height < previous.height { shrink(window, from: previous) } else { settle(window) }
    }

    /// Sizes the window to the panel at rest.
    ///
    /// A spring is still settling by a fraction of a point when its motion is over, in the window's
    /// old coordinates; moving the window under it would carry the panel sideways and snap it back.
    private func settle(_ window: NSWindow) {
        window.contentView?.subviews.forEach { $0.layer?.removeAllAnimations() }
        content?.layer?.removeAllAnimations()
        window.setFrame(frame(around: [rest] + [menu].compactMap(\.self)), display: true)
        place(at: rest, in: window)
        menuHost?.frame = menu.map { local($0, in: window) } ?? .zero
    }

    /// Widens the window to take in `rect` as well as the panel, which stays where it is on screen.
    private func reach(_ rect: CGRect, in window: NSWindow, resting: CGRect? = nil) {
        let resting = resting ?? rest
        window.setFrame(frame(around: [resting, rect]), display: false)
        place(at: resting, in: window)
    }

    private func place(at rect: CGRect, in window: NSWindow) {
        guard let surface else { return }
        shape(surface, to: local(rect, in: window))
        content?.frame = surface.bounds
    }

    /// Gives the panel `rect`, at once or on `motion`, and the fillets joining its top to the top of
    /// the display go with its edges.
    private func shape(_ surface: NSView, to rect: CGRect, on motion: Motion? = nil) {
        for view in body(surface) {
            let frame = (view as? NotchShoulder)?.frame(beside: rect) ?? rect
            if let motion { motion.move(view, to: frame) } else { view.frame = frame }
        }
    }

    /// The panel and its fillets, which are drawn beside it rather than in it, since the panel cuts
    /// its content to its own shape.
    private func body(_ surface: NSView) -> [NSView] {
        [surface] + (surface.superview?.subviews.filter { $0 is NotchShoulder } ?? [])
    }

    private func frame(around rects: [CGRect]) -> CGRect {
        let union = rects.dropFirst().reduce(rects[0]) { $0.union($1) }
        return CGRect(
            x: union.minX - Self.room.width, y: union.minY - Self.room.height,
            width: union.width + Self.room.width * 2, height: union.height + Self.room.height
        )
    }

    private func local(_ rect: CGRect, in window: NSWindow) -> CGRect {
        rect.offsetBy(dx: -window.frame.minX, dy: -window.frame.minY)
    }

    private func make(_ page: TodoPage) -> TodoWindow {
        let frame = frame(around: [rest])
        let window = TodoWindow(frame: frame)
        window.onEscape = { [weak self] in self?.onEscape?() }
        window.onFind = { [weak self] in self?.onFind?() }
        window.onMouseDown = { [weak self] hit in
            guard let self, menu != nil, let host = self.menuHost, hit?.isDescendant(of: host) != true else {
                return false
            }
            return onClickOutsideMenu?() ?? false
        }

        let root = NSView(frame: CGRect(origin: .zero, size: frame.size))
        root.wantsLayer = true
        let surface = SurfaceView(frame: .zero)
        surface.wantsLayer = true
        surface.layer?.backgroundColor = NSColor.black.cgColor
        surface.layer?.cornerRadius = Self.cornerRadius
        // Square where it meets the top of the display, rounded where it hangs.
        surface.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        // The content is cut to the panel's shape while it grows, never drawn outside it.
        surface.layer?.masksToBounds = true
        surface.onExit = { [weak self] in self?.pointerLeft() }
        surface.onEnter = { [weak self] in self?.stopWatchingTheLeave() }
        root.addSubview(surface)
        root.addSubview(NotchShoulder(left: true))
        root.addSubview(NotchShoulder(left: false))
        let content = NSHostingView(rootView: TodoPageView(page: page))
        // Sized by the panel, which follows the height the page measures for itself.
        content.sizingOptions = []
        // Kept at the panel's resting size and pinned to its top centre, the way the page sits.
        content.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        surface.addSubview(content)
        let menuHost = NSHostingView(rootView: RowMenuHost(page: page))
        menuHost.sizingOptions = []
        root.addSubview(menuHost)
        window.contentView = root
        self.window = window
        self.surface = surface
        self.content = content
        self.menuHost = menuHost
        place(at: rest, in: window)
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onDismiss?() }
        }
        return window
    }

    /// Watches where the pointer goes once outside: back in calls the close off, well clear or out
    /// for the whole grace period closes.
    private func pointerLeft() {
        guard leaveMonitors.isEmpty else { return }
        leaveGrace = Task { [weak self] in
            try? await Task.sleep(for: Self.grace)
            guard !Task.isCancelled else { return }
            self?.dismissOnLeave()
        }
        let check: @MainActor () -> Void = { [weak self] in
            guard let self, isWellClear(NSEvent.mouseLocation) else { return }
            dismissOnLeave()
        }
        leaveMonitors = [
            NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { _ in MainActor.assumeIsolated(check) },
            NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { event in
                MainActor.assumeIsolated(check)
                return event
            }
        ].compactMap(\.self)
    }

    private func isWellClear(_ point: CGPoint) -> Bool {
        let dx = max(rest.minX - point.x, 0, point.x - rest.maxX)
        let dy = max(rest.minY - point.y, 0, point.y - rest.maxY)
        return hypot(dx, dy) > Self.reach
    }

    private func dismissOnLeave() {
        stopWatchingTheLeave()
        guard mayCloseOnLeave?() ?? true else { return }
        onDismiss?()
    }

    private func stopWatchingTheLeave() {
        leaveGrace?.cancel()
        leaveGrace = nil
        leaveMonitors.forEach(NSEvent.removeMonitor)
        leaveMonitors = []
    }

    private func stopObserving() {
        stopWatchingTheLeave()
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        window?.onEscape = nil
        window?.onFind = nil
        window?.onMouseDown = nil
        surface?.onExit = nil
        surface?.onEnter = nil
    }
}

extension TodoPanel {
    /// Springs the panel shorter alongside the rows the page takes out, which cutting it short at once
    /// would hide mid-motion. The page's `.snappy`, so the two move as one.
    fileprivate func shrink(_ window: NSWindow, from previous: CGRect) {
        guard let surface else { return }
        isMoving = true
        window.setFrame(frame(around: [previous, rest] + [menu].compactMap(\.self)), display: false)
        place(at: previous, in: window)
        let motion = Motion(duration: 0.5, bounce: 0.15)
        shape(surface, to: local(rest, in: window), on: motion)
        Task { [weak self] in
            await motion.finished()
            guard let self, window === self.window else { return }
            isMoving = false
            settle(window)
        }
    }
}

/// Reports the pointer leaving the panel and coming back. Its tracking area follows its bounds,
/// which are the panel's resting size from the moment it opens.
private final class SurfaceView: NSView {
    var onExit: (@MainActor () -> Void)?
    var onEnter: (@MainActor () -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // `assumeInside`: it opens under the pointer, which never entered it.
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .assumeInside],
            owner: self
        ))
    }

    override func mouseExited(with event: NSEvent) {
        onExit?()
    }

    override func mouseEntered(with event: NSEvent) {
        onEnter?()
    }
}
