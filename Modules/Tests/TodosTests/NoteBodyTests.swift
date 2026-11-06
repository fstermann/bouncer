import AppKit
import Testing

@testable import Todos

@MainActor @Suite struct NoteBodyTests {
    private func shown(_ markdown: String) -> NoteTextView {
        let view = NoteTextView(usingTextLayoutManager: false)
        view.textStorage?.setAttributedString(NoteTextView.attributed(markdown))
        return view
    }

    @Test func showsEachImageAsOneCharacterAndWritesItBackAsWritten() {
        let markdown = "## Notes\nsee ![[a.png|300]] and ![[Weekly sync]]\n![[b.png]]"
        let view = shown(markdown)
        #expect(view.string.count == markdown.count - "![[a.png|300]]".count - "![[b.png]]".count + 2)
        #expect(view.markdown == markdown)
    }

    @Test func oneBackspaceTakesTheWholeImage() {
        let view = shown("x ![[a.png]]")
        view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
        view.deleteBackward(nil)
        #expect(view.markdown == "x ")
    }
}
