import AppKit

/// Catches ⌘V while a field that takes images has focus and the pasteboard holds one, which the
/// field would otherwise drop, and types the embed of the saved image in its place.
@MainActor final class PastedImageKeys {
    private var monitor: Any?
    var images: PastedImages?

    var isActive = false {
        didSet {
            guard isActive != oldValue else { return }
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = isActive ? NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: handle) : nil
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              event.charactersIgnoringModifiers == "v",
              let editor = event.window?.firstResponder as? NSTextView,
              let png = Self.png(on: .general), let embed = images?.save(png)
        else { return event }
        editor.insertText(embed, replacementRange: editor.selectedRange())
        return nil
    }

    /// The pasteboard's image as PNG; `nil` when it holds text too, as a file copied in Finder does
    /// with its icon, which a paste then inserts as text.
    static func png(on pasteboard: NSPasteboard) -> Data? {
        guard pasteboard.string(forType: .string) == nil else { return nil }
        if let png = pasteboard.data(forType: .png) { return png }
        guard let tiff = pasteboard.data(forType: .tiff) else { return nil }
        return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    }
}
