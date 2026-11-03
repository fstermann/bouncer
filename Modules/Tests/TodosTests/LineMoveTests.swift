import Foundation
import Testing

@testable import Todos

@Suite struct LineMoveTests {
    private func moved(_ text: String, _ selection: NSRange, by step: Int) -> (String, NSRange)? {
        guard let edit = LineMove.edit(moving: selection, by: step, in: text) else { return nil }
        let result = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        return (result, edit.selection)
    }

    @Test func movesTheCaretsLineUpKeepingItsColumn() {
        let result = moved("one\ntwo\nthree", NSRange(location: 5, length: 0), by: -1)
        #expect(result?.0 == "two\none\nthree")
        #expect(result?.1 == NSRange(location: 1, length: 0))
    }

    @Test func movesTheLastLineUpThoughItHasNoNewline() {
        let result = moved("one\ntwo", NSRange(location: 6, length: 0), by: -1)
        #expect(result?.0 == "two\none")
        #expect(result?.1 == NSRange(location: 2, length: 0))
    }

    @Test func movesALineDownOntoTheLastLine() {
        let result = moved("one\ntwo", NSRange(location: 1, length: 0), by: 1)
        #expect(result?.0 == "two\none")
        #expect(result?.1 == NSRange(location: 5, length: 0))
    }

    @Test func movesEveryLineTheSelectionTouches() {
        let result = moved("a\nbb\ncc\nd\n", NSRange(location: 3, length: 3), by: 1)
        #expect(result?.0 == "a\nd\nbb\ncc\n")
        #expect(result?.1 == NSRange(location: 5, length: 3))
    }

    @Test func leavesOutTheLineASelectionEndsAtTheStartOf() {
        let result = moved("one\ntwo\nthree", NSRange(location: 4, length: 4), by: -1)
        #expect(result?.0 == "two\none\nthree")
        #expect(result?.1 == NSRange(location: 0, length: 4))
    }

    @Test func stopsAtTheEdges() {
        #expect(moved("one\ntwo", NSRange(location: 1, length: 0), by: -1) == nil)
        #expect(moved("one\ntwo", NSRange(location: 5, length: 0), by: 1) == nil)
        #expect(moved("", NSRange(location: 0, length: 0), by: 1) == nil)
    }

    @Test func countsOffsetsInUTF16() {
        let result = moved("😀x\nab", NSRange(location: 5, length: 0), by: -1)
        #expect(result?.0 == "ab\n😀x")
        #expect(result?.1 == NSRange(location: 1, length: 0))
    }
}
