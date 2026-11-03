import AppKit

/// ⌘⇧← and ⌘⇧→ step to the page before or after the one open in the notch panel.
///
/// Registered only while a page is open, so the apps keep the keys the rest of the time. In a field
/// of Bouncer's own with text in it they still select to the line's start or end, which the hot key
/// would otherwise take from it.
@MainActor
public final class PageKeys {
    /// -1 for the page before, 1 for the one after.
    public var onStep: (@MainActor (Int) -> Void)?
    private var keys: [HotKey] = []

    public init() {}

    public var isActive = false {
        didSet {
            guard isActive != oldValue else { return }
            keys.forEach { $0.unregister() }
            keys = isActive ? [
                HotKey(.previousPage) { [weak self] in self?.step(-1) },
                HotKey(.nextPage) { [weak self] in self?.step(1) }
            ].compactMap(\.self) : []
        }
    }

    private func step(_ step: Int) {
        if let field = NSApp.keyWindow?.firstResponder as? NSTextView, !field.string.isEmpty {
            field.doCommand(by: step < 0
                ? #selector(NSResponder.moveToBeginningOfLineAndModifySelection(_:))
                : #selector(NSResponder.moveToEndOfLineAndModifySelection(_:)))
        } else {
            onStep?(step)
        }
    }
}
