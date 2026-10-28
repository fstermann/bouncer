import AppKit
import SwiftUI

/// A field in the tag row, where a category is named or the todos searched. It takes the cursor
/// itself as it appears: SwiftUI's focus does not move to it in the panel, which never activates
/// Bouncer.
struct PanelField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    /// Bumped to put the cursor back in the field once it is showing.
    var focusRequests = 0
    /// Off for a field kept in place while hidden, which takes the cursor only on request.
    var takesCursorOnAppear = true
    var onSubmit: @MainActor () -> Void = {}
    /// The cursor left the field, by Return, Escape or a click elsewhere.
    let onEnd: @MainActor () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = FocusingTextField()
        field.takesCursorOnAppear = takesCursorOnAppear
        field.placeholderString = placeholder
        field.font = .preferredFont(forTextStyle: .caption1)
        field.textColor = .white
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        if context.coordinator.focusRequests != focusRequests {
            context.coordinator.focusRequests = focusRequests
            field.window?.makeFirstResponder(field)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PanelField
        var focusRequests: Int

        init(parent: PanelField) {
            self.parent = parent
            focusRequests = parent.focusRequests
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            parent.onSubmit()
            return true
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.onEnd()
        }
    }
}

private final class FocusingTextField: NSTextField {
    var takesCursorOnAppear = true

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard takesCursorOnAppear else { return }
        // A turn later, once SwiftUI has finished placing it.
        DispatchQueue.main.async { [weak self] in
            guard let self, let window else { return }
            window.makeFirstResponder(self)
        }
    }
}
