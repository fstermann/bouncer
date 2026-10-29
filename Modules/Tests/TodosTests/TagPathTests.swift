import Testing

@testable import Todos

@Suite struct TagPathTests {
    @Test func aNestedTagNamesItsParentAndLeaf() {
        #expect(TagPath.parent(of: "work/bouncer/ui") == "work/bouncer")
        #expect(TagPath.parent(of: "work") == nil)
        #expect(TagPath.leaf(of: "work/bouncer") == "bouncer")
        #expect(TagPath.leaf(of: "work") == "work")
    }

    @Test func theLineageRunsFromTheOutermostTag() {
        #expect(TagPath.lineage(of: "work/bouncer/ui") == ["work", "work/bouncer", "work/bouncer/ui"])
    }

    @Test func aFilterMatchesItselfAndWhatSitsUnderIt() {
        #expect(TagPath.matches("work", "work"))
        #expect(TagPath.matches("work/bouncer", "work"))
        #expect(!TagPath.matches("workshop", "work"))
        #expect(!TagPath.matches("work", "work/bouncer"))
    }

    @Test func tagsSortAsATreeInTheDraggedOrder() {
        let tags = ["work", "work/infra", "home", "work/bouncer", "later"]
        #expect(TagPath.sorted(tags, by: ["home", "work/bouncer", "work"])
            == ["home", "work", "work/bouncer", "work/infra", "later"])
    }

    @Test func aTagMovesOntoAnotherBesideIt() {
        let tags = ["a", "b", "c"]
        #expect(TagPath.moving("a", onto: "c", in: tags, order: []) == ["b", "c", "a"])
        #expect(TagPath.moving("c", onto: "a", in: tags, order: []) == ["c", "a", "b"])
    }

    @Test func aTagStaysUnderItsOwnParent() {
        let tags = ["work", "work/bouncer", "home"]
        #expect(TagPath.moving("work/bouncer", onto: "home", in: tags, order: ["home"]) == ["home"])
    }

    @Test func hiddenTagsKeepTheirPlaceInTheOrder() {
        #expect(TagPath.moving("c", onto: "a", in: ["a", "c"], order: ["a", "old", "c"]) == ["c", "a", "old"])
    }
}
