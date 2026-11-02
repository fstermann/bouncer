import AppKit
import SwiftUI

/// A time edited the way macOS edits one: a click picks the hour or the minutes, digits replace
/// them, and the arrows step them.
struct TimeField: NSViewRepresentable {
    @Binding var date: Date
    /// Whether it holds the cursor; set false to take it away.
    @Binding var isEditing: Bool

    func makeNSView(context: Context) -> NSDatePicker {
        let picker = EditingDatePicker()
        picker.datePickerStyle = .textField
        picker.datePickerElements = .hourMinute
        picker.isBezeled = false
        picker.isBordered = false
        picker.drawsBackground = false
        picker.focusRingType = .none
        picker.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        picker.textColor = .labelColor
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.changed(_:))
        picker.onEditing = { context.coordinator.parent.isEditing = $0 }
        return picker
    }

    func updateNSView(_ picker: NSDatePicker, context: Context) {
        context.coordinator.parent = self
        if picker.dateValue != date { picker.dateValue = date }
        if !isEditing, picker.window?.firstResponder === picker { picker.window?.makeFirstResponder(nil) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject {
        var parent: TimeField

        init(parent: TimeField) { self.parent = parent }

        @objc func changed(_ picker: NSDatePicker) { parent.date = picker.dateValue }
    }
}

private final class EditingDatePicker: NSDatePicker {
    var onEditing: (Bool) -> Void = { _ in }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { onEditing(true) }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { onEditing(false) }
        return resigned
    }

    /// Return and Escape end the edit, keeping what was typed.
    override func keyDown(with event: NSEvent) {
        if [36, 76, 53].contains(event.keyCode) {
            window?.makeFirstResponder(nil)
        } else {
            super.keyDown(with: event)
        }
    }
}
