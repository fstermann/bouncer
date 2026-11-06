import AppKit

/// `->` and `-->` become `→` as their `>` is typed.
enum TypedArrow {
    /// The dashes before an empty selection at `caret` that `>` turns into an arrow; `nil` when there are none.
    static func dashes(before caret: NSRange, in text: String) -> NSRange? {
        guard caret.length == 0 else { return nil }
        let text = text as NSString
        // Smart dashes, on in the note's text view, have already made `--` into one of these.
        let smartDashes: Set<unichar> = [0x2013, 0x2014]
        if caret.location > 0, smartDashes.contains(text.character(at: caret.location - 1)) {
            return NSRange(location: caret.location - 1, length: 1)
        }
        let dash: unichar = 0x2D
        var start = caret.location
        while start > 0, caret.location - start < 2, text.character(at: start - 1) == dash { start -= 1 }
        return start < caret.location ? NSRange(location: start, length: caret.location - start) : nil
    }
}

/// Watches typing for `>` while a field that takes arrows has focus, and writes `→` in place of it
/// and its dashes, as one undoable change.
@MainActor final class TypedArrowKeys {
    private var monitor: Any?

    var isActive = false {
        didSet {
            guard isActive != oldValue else { return }
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = isActive ? NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: handle) : nil
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard event.characters == ">",
              event.modifierFlags.isDisjoint(with: [.command, .control, .option]),
              let editor = event.window?.firstResponder as? NSTextView,
              let dashes = TypedArrow.dashes(before: editor.selectedRange(), in: editor.string)
        else { return event }
        editor.insertText("→", replacementRange: dashes)
        return nil
    }
}
