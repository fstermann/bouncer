import AppKit
import BouncerFoundation
import MenuBar
import SwiftUI

/// Springs the todo panel into a frame, in AppKit screen coordinates, and returns once it is there.
public typealias Shaping = @MainActor (CGRect) async -> Void

/// A page's window: a black panel that grows out of the notch, or out of a notch-sized point at the
/// top centre of a display without one, the way the notch-style bar does. Switching pages, it grows
/// out of the panel it replaces instead, and goes back into it.
///
/// It opens key, without activating Bouncer, so the page can be typed into straight away. It goes
/// when the user clicks elsewhere or presses Escape, and when the pointer leaves: after a grace
/// period, or at once once it is well clear. The panel changes shape under a still pointer, and a
/// pointer left just outside it has not left.
@MainActor
final class PagePanel<Page: PanelPage> {
    /// The pointer left for good, or the user clicked elsewhere.
    var onDismiss: (@MainActor () -> Void)?
    var onEscape: (@MainActor () -> Void)?
    /// Command-F.
    var onFind: (@MainActor () -> Void)?
    /// Whether the pointer leaving may close the panel: not while something is being typed into it.
    var mayCloseOnLeave: (@MainActor () -> Bool)?
    /// A click landed outside the open menu; returns whether it closed the menu and so is spent.
    var onClickOutsideMenu: (@MainActor () -> Bool)?
    /// Drawn right of the notch, where every page draws it. It sits beside the surface rather than in
    /// it, so it holds still while the surface changes shape.
    let pageButton = PageButton()

    private(set) var window: TodoWindow?
    private var surface: SurfaceView?
    private var content: NSHostingView<Page.Content>?
    private var menuHost: NSHostingView<Page.Menu>?
    private var resignObserver: NSObjectProtocol?
    /// Where the panel rests, and the notch it grows from, in AppKit screen coordinates.
    private var rest: CGRect = .zero
    private var notch: (rect: CGRect, isReal: Bool) = (.zero, true)
    /// Where a row's open menu hangs, in AppKit screen coordinates, past the panel's edge if need be.
    private var menu: CGRect?
    /// Set while the surface is springing, which a refit must not cut short.
    private var isMoving = false
    /// Set while the surface is springing to a refit, which a later refit takes over from.
    private var isReshaping = false
    /// Counts refits, so a spring a later one took over does not settle the panel under it.
    private var reshapes = 0
    private var hasLaidOut = false
    private let leave = LeaveWatch()

    private static var cornerRadius: CGFloat { 12 }
    /// Transparent margin around the panel, so the spring's overshoot is drawn rather than clipped.
    private static var room: CGSize { CGSize(width: 12, height: 4) }

    private static var pointerScreen: NSScreen? {
        NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
    }

    /// - Parameters:
    ///   - screen: whose notch to grow out of, the one under the pointer when `nil`.
    ///   - start: what to grow out of instead of the notch, in screen coordinates.
    func open(
        _ page: Page, on screen: NSScreen?, over duration: TimeInterval?, from start: CGRect?,
        onceCovered: () async -> Void
    ) async {
        let screen = screen ?? Self.pointerScreen
        guard window == nil, let screen else { return }
        hang(page, from: screen)
        let window = make(page)
        guard let surface, let content else { return }
        // Until a page has been laid out once, it has no height to grow towards.
        if !hasLaidOut || duration == nil {
            isMoving = true
            fill(page)
            isMoving = false
        }
        let origin = start ?? notch.rect
        reach(origin, in: window)
        window.orderFrontRegardless()
        window.makeKey()
        guard let duration else {
            await onceCovered()
            return settle(window)
        }
        isMoving = true
        content.alphaValue = 0
        // The content is pinned to the surface's top centre, so the surface reveals it as it grows.
        shape(surface, to: local(origin, in: window))
        if start != nil {
            await appear(in: window, from: origin, over: duration, for: page)
            await onceCovered()
        } else if !notch.isReal {
            body(surface).forEach { $0.alphaValue = 0 }
        }
        // The same springs as the items page, so the two pages grow and focus alike.
        let grow = Motion(duration: duration * 2.4, bounce: 0.1)
        shape(surface, to: local(rest, in: window), on: grow)
        if start == nil, !notch.isReal { body(surface).forEach { grow.fade($0, to: 1) } }
        // Grown out of another page, it is already where that page shows it.
        if start == nil { fadeIn(pageButton, on: grow) }
        // Grown towards the height the page measured last time, and on from mid-flight if it differs.
        if fillOnScreen(window, for: page) { reshape(window) }
        Motion(duration: duration * 1.6, bounce: 0, delay: duration * 0.6, startingWith: grow).focusIn([content])
        await grow.finished()
        settleGrown(window)
    }

    /// Settles the panel once it has grown, unless a reshape carries it on and settles it on landing.
    private func settleGrown(_ window: NSWindow) {
        guard window === self.window, let content else { return }
        Motion.unfocus([content])
        guard !isReshaping else { return }
        isMoving = false
        settle(window)
    }

    /// Fades in over the panel it replaces, which is only taken away once it is covered.
    private func appear(in window: NSWindow, from origin: CGRect, over duration: TimeInterval, for page: Page) async {
        guard let surface else { return }
        let appear = Motion(duration: duration * 0.6, bounce: 0)
        for view in body(surface) {
            view.alphaValue = 0
            appear.fade(view, to: 1)
        }
        if fillOnScreen(window, for: page) {
            reach(origin, in: window)
            shape(surface, to: local(origin, in: window))
        }
        await appear.finished()
    }

    /// Fills the panel, if it is still empty, once its first motion is on screen rather than after the
    /// layout. Returns whether the page measured another height than the one it was growing towards.
    private func fillOnScreen(_ window: NSWindow, for page: Page) -> Bool {
        guard content?.superview == nil else { return false }
        let measured = rest
        window.displayIfNeeded()
        CATransaction.flush()
        fill(page)
        return rest != measured
    }

    /// Adds the page to the panel and lays it out, which takes the todo page some 90 ms. Laid out while
    /// held as moving, so the heights it measures only set where it rests.
    private func fill(_ page: Page) {
        guard let surface, let content else { return }
        surface.addSubview(content)
        surface.resizeSubviews(withOldSize: surface.bounds.size)
        content.layoutSubtreeIfNeeded()
        hasLaidOut = true
        page.focusRequests += 1
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
        isReshaping = false
        reshapes += 1
        if let duration, let content { Motion(duration: duration * 1.6, bounce: 0).focusOut([content]) }
        var isShaped = false
        await items? { [self] frame in
            isShaped = true
            guard let duration else { return }
            reach(frame, in: window, resting: rest, surface: surface)
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
            reach(notch.rect, in: window, resting: rest, surface: surface)
            let gather = Motion(duration: duration * 1.6, bounce: 0)
            shape(surface, to: local(notch.rect, in: window), on: gather)
            if !notch.isReal { body(surface).forEach { gather.fade($0, to: 0) } }
            if pageButton.window === window { gather.fade(pageButton, to: 0) }
            await gather.finished()
        }
        window.orderOut(nil)
    }

    /// Where the panel rests while it is open, in AppKit screen coordinates.
    var frame: CGRect? { window == nil ? nil : rest }

    /// Fits the panel to the page's height, keeping its top against the top of the display.
    func fit(_ page: Page) {
        guard let window else { return }
        let previous = rest
        rest = CGRect(x: rest.minX, y: rest.maxY - page.height, width: rest.width, height: page.height)
        menu = page.menuFrame(in: rest)
        guard !isMoving || isReshaping else { return }
        // A menu that changed size mid-spring hangs in the window, or in one the spring carries on in.
        let menuFits = menu.map { window.frame.contains(frame(around: [$0])) } ?? true
        if rest.height != previous.height || isReshaping && !menuFits {
            reshape(window)
        } else if isReshaping {
            menuHost?.frame = menu.map { local($0, in: window) } ?? .zero
        } else {
            settle(window)
        }
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
    /// - Parameter surface: the panel's, for one closing, which has already let go of it.
    private func reach(_ rect: CGRect, in window: NSWindow, resting: CGRect? = nil, surface: NSView? = nil) {
        let resting = resting ?? rest
        window.setFrame(frame(around: [resting, rect]), display: false)
        place(at: resting, in: window, surface: surface)
    }

    private func place(at rect: CGRect, in window: NSWindow, surface: NSView? = nil) {
        guard let surface = surface ?? self.surface else { return }
        shape(surface, to: local(rect, in: window))
        content?.frame = surface.bounds
        if pageButton.window === window { placeButton(in: window) }
    }

    private func make(_ page: Page) -> TodoWindow {
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
        window.cursorOverride = { [weak self] point in
            guard let self, menu != nil, let host = self.menuHost, host.frame.contains(point) else { return nil }
            return .arrow
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
        surface.onEnter = { [weak self] in self?.leave.stop() }
        root.addSubview(surface)
        root.addSubview(NotchShoulder(left: true))
        root.addSubview(NotchShoulder(left: false))
        root.addSubview(pageButton)
        // A close into the notch left it faded out.
        pageButton.alphaValue = 1
        let content = NSHostingView(rootView: page.view)
        // Sized by the panel, which follows the height the page measures for itself.
        content.sizingOptions = []
        // Kept at the panel's resting size; the surface pins it to its top centre once `fill` adds it.
        let menuHost = NSHostingView(rootView: page.menuView)
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
            MainActor.assumeIsolated {
                // Another page growing out of this one, which takes this away once covered.
                guard self?.window?.isHiddenForScreenshot != true, !(NSApp.keyWindow is TodoWindow) else { return }
                self?.onDismiss?()
            }
        }
        return window
    }

    private func pointerLeft() {
        leave.start(
            around: { [weak self] in self?.rest ?? .zero },
            onLeave: { [weak self] in self?.dismissOnLeave() }
        )
    }

    private func dismissOnLeave() {
        guard window?.isHiddenForScreenshot != true, mayCloseOnLeave?() ?? true else { return }
        onDismiss?()
    }

    private func stopObserving() {
        leave.stop()
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        window?.onEscape = nil
        window?.onFind = nil
        window?.onMouseDown = nil
        surface?.onExit = nil
        surface?.onEnter = nil
    }
}

extension PagePanel {
    /// Finds `screen`'s notch, and where `page` rests hanging from it.
    fileprivate func hang(_ page: Page, from screen: NSScreen) {
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
            x: notch.rect.midX - page.width / 2, y: top - page.height, width: page.width, height: page.height
        )
    }

    /// Right of the notch, on whole points, where the items page's button lands, since the notch's
    /// edge can fall between.
    fileprivate func placeButton(in window: NSWindow) {
        let left = notch.rect.maxX.rounded(.down) + PageButton.gap - window.frame.minX
        pageButton.place(atX: left, midY: notch.rect.midY - window.frame.minY)
    }

    /// Gives the panel `rect`, at once or on `motion`, and the fillets joining its top to the top of
    /// the display go with its edges.
    fileprivate func shape(_ surface: NSView, to rect: CGRect, on motion: Motion? = nil) {
        for view in body(surface) {
            let frame = (view as? NotchShoulder)?.frame(beside: rect) ?? rect
            if let motion { motion.move(view, to: frame) } else { view.frame = frame }
        }
    }

    fileprivate func frame(around rects: [CGRect]) -> CGRect {
        let union = rects.dropFirst().reduce(rects[0]) { $0.union($1) }
        return CGRect(
            x: union.minX - Self.room.width, y: union.minY - Self.room.height,
            width: union.width + Self.room.width * 2, height: union.height + Self.room.height
        )
    }

    /// Springs the panel from where it is drawn, mid-flight if need be, to the page's new height: with the
    /// rows leaving, or revealing the page at full height. The page's `.snappy`, so the two move as one.
    fileprivate func reshape(_ window: NSWindow) {
        guard let surface, let content else { return }
        let shown = (surface.layer?.presentation()?.frame ?? surface.frame)
            .offsetBy(dx: window.frame.minX, dy: window.frame.minY)
        isMoving = true
        isReshaping = true
        reshapes += 1
        let reshape = reshapes
        for view in body(surface) + [content] { view.layer?.removeAllAnimations() }
        window.setFrame(frame(around: [shown, rest] + [menu].compactMap(\.self)), display: false)
        place(at: shown, in: window)
        menuHost?.frame = menu.map { local($0, in: window) } ?? .zero
        let height = max(shown.height, rest.height)
        content.frame = CGRect(x: 0, y: surface.bounds.height - height, width: rest.width, height: height)
        let motion = Motion(duration: 0.5, bounce: 0.15)
        shape(surface, to: local(rest, in: window), on: motion)
        Task { [weak self] in
            await motion.finished()
            guard let self, window === self.window, reshape == reshapes else { return }
            isMoving = false
            isReshaping = false
            settle(window)
        }
    }
}
