import AppKit

/// The overview's window: borderless, over every other window on one display, Spaces and full screen
/// apps included. It becomes key without activating Bouncer, so Escape reaches it and the app the
/// user was in stays frontmost until they pick a window.
final class OverlayPanel: NSPanel {
    var onEscape: (@MainActor () -> Void)?
    /// Tab; returns whether it was taken, so a text field being typed in keeps it otherwise.
    var onTab: (@MainActor () -> Bool)?

    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override func sendEvent(_ event: NSEvent) {
        let plainTab = event.type == .keyDown && event.keyCode == 48
            && event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock).isEmpty
        if plainTab, onTab?() == true { return }
        super.sendEvent(event)
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}
