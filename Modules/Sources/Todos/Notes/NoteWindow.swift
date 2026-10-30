import AppKit
import SwiftUI

/// A note popped out of the panel into a window of its own, which stays over other apps' windows
/// and on every space for as long as the meeting runs. It becomes key without activating Bouncer,
/// as the panel does, so the app the meeting is in stays frontmost.
@MainActor
final class NoteWindow: NSPanel {
    let draft: NoteDraft
    var onClose: (@MainActor (NoteWindow) -> Void)?

    init(
        draft: NoteDraft, known: NoteSuggestions, onEdit: @escaping (NoteDraft) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.draft = draft
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: NotePage.width, height: 520),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel, .utilityWindow],
            backing: .buffered, defer: false
        )
        isReleasedWhenClosed = false
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        backgroundColor = .black
        appearance = NSAppearance(named: .darkAqua)
        minSize = CGSize(width: 360, height: 320)
        let editor = NoteEditor(draft: draft, known: known, onEdit: onEdit, onDelete: onDelete, fillsHeight: true)
            .padding(.top, 28)
            .foregroundStyle(.white)
            .environment(\.colorScheme, .dark)
        contentView = NSHostingView(rootView: editor)
        setFrameAutosaveName("NoteWindow")
    }

    override var canBecomeKey: Bool { true }

    override func close() {
        super.close()
        onClose?(self)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        EditShortcuts.perform(event, in: self) || super.performKeyEquivalent(with: event)
    }
}
