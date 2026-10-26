import AppKit
import SwiftUI

/// The field a category is named in. It takes the cursor itself as it appears: SwiftUI's focus
/// does not move to it in the panel, which never activates Bouncer.
struct CategoryField: NSViewRepresentable {
    @Binding var text: String
    let onSubmit: @MainActor () -> Void
    /// The cursor left the field, by Return, Escape or a click elsewhere.
    let onEnd: @MainActor () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = FocusingTextField()
        field.placeholderString = "Category"
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
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CategoryField

        init(parent: CategoryField) { self.parent = parent }

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
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // A turn later, once SwiftUI has finished placing it.
        DispatchQueue.main.async { [weak self] in
            guard let self, let window else { return }
            window.makeFirstResponder(self)
        }
    }
}
