import Foundation
import Testing

@testable import Todos

@Suite struct ListTypingTests {
    /// `text` with the edit Return makes at its end applied, and where the cursor lands.
    private func returned(_ text: String) -> (String, Int)? {
        let caret = NSRange(location: (text as NSString).length, length: 0)
        return ListTyping.newline(at: caret, in: text).map(apply(to: text))
    }

    private func tabbed(_ text: String, deeper: Bool = true) -> (String, Int)? {
        let caret = NSRange(location: (text as NSString).length, length: 0)
        return ListTyping.indenting(at: caret, in: text, deeper: deeper).map(apply(to: text))
    }

    private func apply(to text: String) -> (ListTyping.Edit) -> (String, Int) {
        { ((text as NSString).replacingCharacters(in: $0.range, with: $0.replacement), $0.caret) }
    }

    @Test func returnContinuesTheList() {
        #expect(returned("- milk")?.0 == "- milk\n- ")
        #expect(returned("* milk")?.0 == "* milk\n* ")
        #expect(returned("\t- milk")?.0 == "\t- milk\n\t- ")
        #expect(returned("- milk")?.1 == 9)
    }

    @Test func returnCountsANumberedListOn() {
        #expect(returned("1. one")?.0 == "1. one\n2. ")
        #expect(returned("9) nine")?.0 == "9) nine\n10) ")
    }

    @Test func returnStartsAnOpenTaskAfterAnyTask() {
        #expect(returned("- [ ] call")?.0 == "- [ ] call\n- [ ] ")
        #expect(returned("- [x] called")?.0 == "- [x] called\n- [ ] ")
    }

    @Test func returnOnAnEmptyItemEndsTheList() {
        #expect(returned("- milk\n- ")?.0 == "- milk\n")
        #expect(returned("- milk\n\t- ")?.0 == "- milk\n\t")
        #expect(returned("- [ ] ")?.0 == "")
    }

    @Test func returnOutsideAListIsAPlainNewLine() {
        #expect(returned("Notes") == nil)
        #expect(returned("-not a list") == nil)
        #expect(returned("") == nil)
    }

    @Test func returnInsideAnItemSplitsIt() {
        let text = "- milk and eggs"
        let edit = ListTyping.newline(at: NSRange(location: 6, length: 0), in: text)
        #expect(edit.map(apply(to: text))?.0 == "- milk\n-  and eggs")
    }

    @Test func tabNestsAnItemAndShiftTabBringsItOut() {
        #expect(tabbed("- milk")?.0 == "\t- milk")
        #expect(tabbed("\t- milk", deeper: false)?.0 == "- milk")
        #expect(tabbed("    - milk", deeper: false)?.0 == "- milk")
        #expect(tabbed("- milk", deeper: false) == nil)
        #expect(tabbed("plain") == nil)
    }

    @Test func aNestedNumberedItemStartsAtOne() {
        #expect(tabbed("1. one\n2. ")?.0 == "1. one\n\t1. ")
    }

    @Test func onlyTheCaretsLineChanges() {
        #expect(returned("- a\n- b")?.0 == "- a\n- b\n- ")
        #expect(tabbed("- a\n- b")?.0 == "- a\n\t- b")
    }
}
