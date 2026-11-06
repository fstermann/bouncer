import Foundation
import Testing

@testable import Todos

@Suite struct TypedArrowTests {
    private func dashes(_ text: String, caret: Int, selected: Int = 0) -> NSRange? {
        TypedArrow.dashes(before: NSRange(location: caret, length: selected), in: text)
    }

    @Test func takesTheOneOrTwoDashesBeforeTheCaret() {
        #expect(dashes("a -", caret: 3) == NSRange(location: 2, length: 1))
        #expect(dashes("a --", caret: 4) == NSRange(location: 2, length: 2))
        #expect(dashes("---", caret: 3) == NSRange(location: 1, length: 2))
    }

    @Test func takesADashSmartDashesMadeOfTwo() {
        #expect(dashes("a \u{2014}", caret: 3) == NSRange(location: 2, length: 1))
        #expect(dashes("a \u{2013}", caret: 3) == NSRange(location: 2, length: 1))
    }

    @Test func leavesAGreaterThanWithoutDashes() {
        #expect(dashes("a ", caret: 2) == nil)
        #expect(dashes("", caret: 0) == nil)
        #expect(dashes("--", caret: 1, selected: 1) == nil)
    }
}
