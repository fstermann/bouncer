import Testing

@testable import Todos

@Suite struct TagCompletionTests {
    private let tags = ["work", "home", "homework", "errands"]

    @Test func offersTagsStartingWithTheWordFirstThenContainingThenLoosely() {
        #expect(TagCompletion.suggestions(for: "Call bank #wo", from: tags) == ["work", "homework"])
        #expect(TagCompletion.suggestions(for: "Call bank #hm", from: tags) == ["home", "homework"])
        #expect(TagCompletion.suggestions(for: "Call bank #", from: tags) == tags)
    }

    @Test func offersNothingOutsideATagOrForOnesAlreadyThere() {
        #expect(TagCompletion.suggestions(for: "Call bank", from: tags).isEmpty)
        #expect(TagCompletion.suggestions(for: "Call #work ", from: tags).isEmpty)
        #expect(TagCompletion.suggestions(for: "Call ##", from: tags).isEmpty)
        #expect(TagCompletion.suggestions(for: "Call\nnote #wo", from: tags).isEmpty)
        #expect(TagCompletion.suggestions(for: "Call #work #wo", from: tags) == ["homework"])
    }

    @Test func offersANoteTheTagsItLacksForWhatIsTyped() {
        #expect(TagCompletion.suggestions(for: "", carrying: ["home"], from: tags) == ["work", "homework", "errands"])
        #expect(TagCompletion.suggestions(for: "#wo", carrying: ["work"], from: tags) == ["homework"])
    }

    @Test func readsTheTagTypedIntoANote() {
        #expect(TagCompletion.tag(from: "#work/bouncer, ") == "work/bouncer")
        #expect(TagCompletion.tag(from: " ,") == nil)
        #expect(TagCompletion.tag(from: "#") == nil)
    }

    @Test func completingReplacesTheWordBeingTyped() {
        #expect(TagCompletion.completing("Call bank #wo", with: "work") == "Call bank #work ")
    }

    @Test func togglingAddsOrRemovesATagOnTheFirstLine() {
        #expect(TagCompletion.toggling("work", in: "Call bank") == "Call bank #work ")
        #expect(TagCompletion.toggling("work", in: "") == "#work ")
        #expect(TagCompletion.toggling("work", in: "Call #work bank\nnote") == "Call bank\nnote")
    }
}
