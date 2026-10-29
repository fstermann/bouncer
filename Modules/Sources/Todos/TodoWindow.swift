import AppKit

/// Becomes key for typing without activating Bouncer, the way Spotlight does, and sits in the menu
/// bar band, which AppKit otherwise pushes windows out of.
final class TodoWindow: NSPanel {
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

    /// A click about to be handled, and the view it lands on; returning `true` swallows it.
    var onMouseDown: (@MainActor (NSView?) -> Bool)?
    /// The cursor for a point in the window, over whatever the views there set. A text field sets its
    /// I-beam as the pointer enters it even under a view drawn on top of it.
    var cursorOverride: (@MainActor (CGPoint) -> NSCursor?)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, let contentView,
           onMouseDown?(contentView.hitTest(contentView.convert(event.locationInWindow, from: nil))) == true {
            return
        }
        super.sendEvent(event)
        if Self.pointerEvents.contains(event.type), let cursor = cursorOverride?(mouseLocationOutsideOfEventStream) {
            cursor.set()
        }
    }

    private static let pointerEvents: Set<NSEvent.EventType> = [.mouseMoved, .mouseEntered, .mouseExited, .cursorUpdate]

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    var onFind: (@MainActor () -> Void)?

    /// Bouncer has no Edit menu to carry the editing shortcuts, so the panel maps them itself.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else {
            return super.performKeyEquivalent(with: event)
        }
        let key = event.charactersIgnoringModifiers ?? ""
        if key == "f", let onFind {
            onFind()
            return true
        }
        if let action = Self.editActions[key], let firstResponder, firstResponder.tryToPerform(action, with: self) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private static let editActions: [String: Selector] = [
        "x": #selector(NSText.cut(_:)),
        "c": #selector(NSText.copy(_:)),
        "v": #selector(NSText.paste(_:)),
        "a": #selector(NSText.selectAll(_:))
    ]
}
