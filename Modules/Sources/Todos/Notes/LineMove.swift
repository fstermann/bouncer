import AppKit

/// ⌥↑ and ⌥↓ in a note: the lines the selection touches swap with the line above or below.
enum LineMove {
    struct Edit: Equatable {
        /// What is rewritten, in UTF-16 offsets as `NSTextView` counts them.
        var range: NSRange
        var replacement: String
        var selection: NSRange
    }

    /// The edit moving the selected lines one line up (`step` -1) or down (1); `nil` at the text's edge.
    static func edit(moving selection: NSRange, by step: Int, in text: String) -> Edit? {
        let text = text as NSString
        // A selection ending at a line's start, as a triple click leaves it, leaves that line out.
        let endsAtLineStart = selection.length > 0 && text.character(at: NSMaxRange(selection) - 1) == 0x0A
        let block = text.lineRange(for: NSRange(location: selection.location,
                                                length: selection.length - (endsAtLineStart ? 1 : 0)))
        let neighbour: NSRange
        if step < 0 {
            guard block.location > 0 else { return nil }
            neighbour = text.lineRange(for: NSRange(location: block.location - 1, length: 0))
        } else {
            guard NSMaxRange(block) < text.length else { return nil }
            neighbour = text.lineRange(for: NSRange(location: NSMaxRange(block), length: 0))
        }
        let (first, second) = step < 0 ? (neighbour, block) : (block, neighbour)
        let lines = text.substring(with: NSRange(location: first.location, length: NSMaxRange(second) - first.location))
        let firstText = withoutNewline(text.substring(with: first))
        let secondText = withoutNewline(text.substring(with: second))
        let trailing = lines.hasSuffix("\n") ? "\n" : ""
        let shift = (step < 0 ? -1 : 1) * ((step < 0 ? firstText : secondText).utf16.count + 1)
        return Edit(
            range: NSRange(location: first.location, length: (lines as NSString).length),
            replacement: secondText + "\n" + firstText + trailing,
            selection: NSRange(location: selection.location + shift, length: selection.length)
        )
    }

    private static func withoutNewline(_ line: String) -> String {
        line.hasSuffix("\n") ? String(line.dropLast()) : line
    }
}

/// Catches ⌥↑ and ⌥↓ before the note's text view reads them as moves to a paragraph's edge, which
/// it does before SwiftUI's key handlers see them. On only while the note has focus.
@MainActor final class LineMoveKeys {
    private var monitor: Any?

    var isActive = false {
        didSet {
            guard isActive != oldValue else { return }
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = isActive ? NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: handle) : nil
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        let step: Int? = switch event.keyCode {
        case 126: -1
        case 125: 1
        default: nil
        }
        guard let step,
              event.modifierFlags.intersection([.command, .shift, .control, .option]) == .option,
              let editor = event.window?.firstResponder as? NSTextView, !editor.isFieldEditor else { return event }
        editor.moveSelectedLines(by: step)
        return nil
    }
}

extension NSTextView {
    /// Moves the selected lines as one undoable change; `false` when there is no line to swap with.
    @discardableResult func moveSelectedLines(by step: Int) -> Bool {
        guard let edit = LineMove.edit(moving: selectedRange(), by: step, in: string),
              shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return false }
        textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
        didChangeText()
        setSelectedRange(edit.selection)
        scrollRangeToVisible(edit.selection)
        return true
    }
}
