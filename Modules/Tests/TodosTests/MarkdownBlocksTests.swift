import Testing

@testable import Todos

@Suite struct MarkdownBlocksTests {
    @Test func paragraphsSplitAtBlankLinesAndKeepTheirLineBreaks() {
        #expect(MarkdownBlock.parse("one\ntwo\n\nthree") == [.paragraph("one\ntwo"), .paragraph("three")])
    }

    @Test func headingsNeedASpaceAfterTheHashes() {
        #expect(MarkdownBlock.parse("## Setup\n#tag") == [.heading("Setup"), .paragraph("#tag")])
    }

    @Test func listsKeepTheirMarkersAndNesting() {
        let text = "- one\n  - inner\n2. two\n3) three"
        #expect(MarkdownBlock.parse(text) == [
            .item(marker: "•", text: "one", depth: 0),
            .item(marker: "•", text: "inner", depth: 1),
            .item(marker: "2.", text: "two", depth: 0),
            .item(marker: "3.", text: "three", depth: 0)
        ])
    }

    @Test func anIndentedLineContinuesTheItemAboveIt() {
        #expect(MarkdownBlock.parse("- a long\n  item") == [.item(marker: "•", text: "a long\nitem", depth: 0)])
    }

    @Test func fencedCodeIsKeptVerbatim() {
        let text = "Run:\n```sh\nmake test\n  # - not a list\n```\nDone."
        #expect(MarkdownBlock.parse(text) == [
            .paragraph("Run:"), .code("make test\n  # - not a list"), .paragraph("Done.")
        ])
    }

    @Test func anUnclosedFenceRunsToTheEnd() {
        #expect(MarkdownBlock.parse("```\nstill streaming") == [.code("still streaming")])
    }

    @Test func tablesQuotesAndRules() {
        let text = "| a | b |\n|---|:-:|\n| 1 | `x` |\n> said\n---"
        #expect(MarkdownBlock.parse(text) == [.table([["a", "b"], ["1", "`x`"]]), .quote("said"), .rule])
    }

    @Test func pipesWithoutAHeaderRuleStayAsWritten() {
        #expect(MarkdownBlock.parse("| a | b |\n| c | d |") == [.code("| a | b |\n| c | d |")])
    }
}
