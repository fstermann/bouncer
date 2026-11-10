import Testing

@testable import Todos

@Suite struct TagRenameTests {
    @Test func aTagAndTheTagsUnderItAreRenamed() {
        #expect(TagRename.renamed("work", from: "work", to: "job") == "job")
        #expect(TagRename.renamed("work/bouncer", from: "work", to: "job") == "job/bouncer")
        #expect(TagRename.renamed("workshop", from: "work", to: "job") == "workshop")
        #expect(TagRename.renamed("home", from: "work", to: "job") == "home")
    }

    @Test func aTypedNameIsCleaned() {
        #expect(TagRename.cleaned(" #job ") == "job")
        #expect(TagRename.cleaned("job/infra") == "job/infra")
        #expect(TagRename.cleaned("") == nil)
        #expect(TagRename.cleaned("two words") == nil)
        #expect(TagRename.cleaned("job/") == nil)
    }

    @Test func theTodoFileIsRenamedInTasksCategoriesAndColours() {
        let markdown = """
        ---
        categories:
          - work
          - home
        tag-colors:
          work: blue
          work/bouncer: green
        ---
        - [ ] A #work 📅 2026-11-10
        - [x] B #work/bouncer #home
        - [ ] C #workshop
          a note on #work
        Plain text #work
        """
        let renamed = TagRename.renaming("work", to: "job", in: markdown)
        #expect(Categories.parse(renamed) == ["home", "job"])
        #expect(FileTagColors.parse(renamed) == ["job": "blue", "job/bouncer": "green"])
        #expect(TodoList.parse(renamed).map(\.tags) == [["job"], ["job/bouncer", "home"], ["workshop"]])
        #expect(renamed.contains("- [ ] A #job 📅 2026-11-10\n"))
        #expect(renamed.contains("  a note on #work\nPlain text #work"))
    }

    @Test func aFileWithoutTheTagIsLeftAsItWas() {
        let markdown = "- [ ] A #home\n"
        #expect(TagRename.renaming("work", to: "job", in: markdown) == markdown)
    }

    @Test func orderAndNoteTagsKeepEachTagOnce() {
        #expect(TagRename.order(["job", "home", "work"], from: "work", to: "job") == ["job", "home"])
        #expect(TagRename.noteTags(["work", "job"], from: "work", to: "job") == ["job"])
        #expect(TagRename.noteTags(["home"], from: "work", to: "job") == nil)
        let repositories = TagRename.keys(of: ["work/x": "/a", "home": "/b"], from: "work", to: "job")
        #expect(repositories == ["job/x": "/a", "home": "/b"])
    }
}
