import AppKit
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
    /// Whether the pointer leaving may close the panel: not while something is being typed into it.
    var mayCloseOnLeave: (@MainActor () -> Bool)?

    private var window: TodoWindow?
    private var surface: SurfaceView?
    private var content: NSHostingView<TodoPageView>?
    private var resignObserver: NSObjectProtocol?
    /// Where the panel rests, and the notch it grows from, in AppKit screen coordinates.
    private var rest: CGRect = .zero
    private var notch: (rect: CGRect, isReal: Bool) = (.zero, true)
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

    /// - Parameter start: what to grow out of instead of the notch, in screen coordinates.
    func open(
        _ page: TodoPage, over duration: TimeInterval?, from start: CGRect?, onceCovered: () async -> Void
    ) async {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
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
        content.alphaValue = 0
        window.orderFrontRegardless()
        window.makeKey()
        page.focusRequests += 1
        guard let duration else {
            content.alphaValue = 1
            await onceCovered()
            return settle(window)
        }
        isMoving = true
        surface.frame = local(origin, in: window)
        if start != nil {
            // Fades in over the panel it replaces, which is only taken away once it is covered.
            surface.alphaValue = 0
            fade(surface, to: 1, over: duration * 0.6)
            try? await Task.sleep(for: .seconds(duration * 0.6))
            await onceCovered()
        } else if !notch.isReal {
            surface.alphaValue = 0
            fade(surface, to: 1, over: duration * 2.4)
        }
        let grow = duration * 2.4
        Spring(duration: grow, bounce: 0.1).move(surface, to: local(rest, in: window))
        try? await Task.sleep(for: .seconds(duration * 0.6))
        fade(content, to: 1, over: duration * 1.6)
        try? await Task.sleep(for: .seconds(grow - duration * 0.6))
        isMoving = false
        if window === self.window { settle(window) }
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
        isMoving = false
        if let duration { fade(content, to: 0, over: duration * 0.6) }
        var isShaped = false
        await items? { [self] frame in
            isShaped = true
            guard let duration else { return }
            reach(frame, in: window, resting: rest)
            let gather = duration * 1.6
            Spring(duration: gather, bounce: 0).move(surface, to: local(frame, in: window))
            try? await Task.sleep(for: .seconds(gather))
        }
        guard let duration else { return window.orderOut(nil) }
        if isShaped {
            // Shaped like the panel underneath by now, and faded off it rather than lifted.
            fade(window.contentView, to: 0, over: duration * 0.6)
            try? await Task.sleep(for: .seconds(duration * 0.6))
        } else {
            reach(notch.rect, in: window, resting: rest)
            let gather = duration * 1.6
            Spring(duration: gather, bounce: 0).move(surface, to: local(notch.rect, in: window))
            if !notch.isReal { fade(surface, to: 0, over: gather) }
            try? await Task.sleep(for: .seconds(gather))
        }
        window.orderOut(nil)
    }

    /// Fits the panel to the page's height, keeping its top against the top of the display.
    func fit(_ page: TodoPage) {
        guard let window else { return }
        rest = CGRect(x: rest.minX, y: rest.maxY - page.height, width: rest.width, height: page.height)
        if !isMoving { settle(window) }
    }

    /// Sizes the window to the panel at rest.
    ///
    /// A spring is still settling by a fraction of a point when its motion is over, in the window's
    /// old coordinates; moving the window under it would carry the panel sideways and snap it back.
    private func settle(_ window: NSWindow) {
        window.contentView?.subviews.forEach { $0.layer?.removeAllAnimations() }
        window.setFrame(frame(around: [rest]), display: true)
        place(at: rest, in: window)
    }

    /// Widens the window to take in `rect` as well as the panel, which stays where it is on screen.
    private func reach(_ rect: CGRect, in window: NSWindow, resting: CGRect? = nil) {
        let resting = resting ?? rest
        window.setFrame(frame(around: [resting, rect]), display: false)
        place(at: resting, in: window)
    }

    private func place(at rect: CGRect, in window: NSWindow) {
        let frame = local(rect, in: window)
        window.contentView?.subviews.forEach { $0.frame = frame }
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

        let root = NSView(frame: CGRect(origin: .zero, size: frame.size))
        root.wantsLayer = true
        let surface = SurfaceView(frame: .zero)
        surface.wantsLayer = true
        surface.layer?.backgroundColor = NSColor.black.cgColor
        surface.layer?.cornerRadius = Self.cornerRadius
        // Square where it meets the top of the display, rounded where it hangs.
        surface.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        surface.onExit = { [weak self] in self?.pointerLeft() }
        surface.onEnter = { [weak self] in self?.stopWatchingTheLeave() }
        root.addSubview(surface)
        let content = NSHostingView(rootView: TodoPageView(page: page))
        // Sized by the panel, which follows the height the page measures for itself.
        content.sizingOptions = []
        root.addSubview(content)
        window.contentView = root
        place(at: rest, in: window)

        self.window = window
        self.surface = surface
        self.content = content
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
        surface?.onExit = nil
        surface?.onEnter = nil
    }

    private func fade(_ view: NSView?, to alpha: CGFloat, over duration: TimeInterval) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            view?.animator().alphaValue = alpha
        }
    }
}

/// A Core Animation spring on a view's frame, started from wherever it is on screen now, so a
/// close that interrupts an open turns around mid-flight instead of jumping.
@MainActor
private struct Spring {
    let duration: TimeInterval
    let bounce: CGFloat

    func move(_ view: NSView, to frame: CGRect) {
        guard let layer = view.layer else { return view.frame = frame }
        // On screen only while something is moving it: at rest the presentation copy can still be
        // in the coordinates of a window that has just been resized.
        let shown = (layer.animationKeys() ?? []).isEmpty ? layer : layer.presentation() ?? layer
        let position = shown.position, bounds = shown.bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.frame = frame
        CATransaction.commit()
        animate(layer, "position", from: NSValue(point: position), to: NSValue(point: layer.position))
        animate(layer, "bounds", from: NSValue(rect: bounds), to: NSValue(rect: layer.bounds))
    }

    private func animate(_ layer: CALayer, _ keyPath: String, from: Any, to: Any) {
        let animation = CASpringAnimation(perceptualDuration: duration, bounce: bounce)
        animation.keyPath = keyPath
        animation.fromValue = from
        animation.toValue = to
        animation.duration = animation.settlingDuration
        layer.add(animation, forKey: keyPath)
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

/// Becomes key for typing without activating Bouncer, the way Spotlight does, and sits in the menu
/// bar band, which AppKit otherwise pushes windows out of.
private final class TodoWindow: NSPanel {
    var onEscape: (@MainActor () -> Void)?

    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // Above every window of the items panel, which it grows out of and goes back into.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 4)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}
