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
        // The system would scale it in as it appears, pulling its top edge off the display's.
        animationBehavior = .none
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

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "f", let onFind {
            onFind()
            return true
        }
        return EditShortcuts.perform(event, in: self) || super.performKeyEquivalent(with: event)
    }
}

/// Bouncer has no Edit menu to carry the editing shortcuts, so its windows map them themselves.
@MainActor
enum EditShortcuts {
    static func perform(_ event: NSEvent, in window: NSWindow) -> Bool {
        guard let responder = window.firstResponder else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if key == "z", flags == .command || flags == [.command, .shift], let undo = responder.undoManager {
            let redoes = flags.contains(.shift)
            guard redoes ? undo.canRedo : undo.canUndo else { return false }
            if redoes { undo.redo() } else { undo.undo() }
            return true
        }
        guard flags == .command, let action = actions[key] else { return false }
        return responder.tryToPerform(action, with: window)
    }

    private static let actions: [String: Selector] = [
        "x": #selector(NSText.cut(_:)),
        "c": #selector(NSText.copy(_:)),
        "v": #selector(NSText.paste(_:)),
        "a": #selector(NSText.selectAll(_:))
    ]
}
