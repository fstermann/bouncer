import Testing

@testable import Todos

@Suite struct FileTagColorsTests {
    @Test func aFileWithoutColoursKeepsNone() {
        #expect(FileTagColors.parse("- [ ] Buy milk\n") == nil)
        #expect(FileTagColors.parse("---\ncategories:\n  - work\n---\n- [ ] A\n") == nil)
    }

    @Test func coloursAreReadFromTheFrontmatter() {
        let markdown = "---\ntag-colors:\n  work: blue\n  \"home/garden\": green\n---\n- [ ] A\n"
        #expect(FileTagColors.parse(markdown) == ["work": "blue", "home/garden": "green"])
        #expect(FileTagColors.parse("---\ntag-colors:\n---\n") == [:])
    }

    @Test func settingKeepsTheRestOfTheFile() {
        let markdown = "---\ncategories:\n  - work\n---\n- [ ] A #work\n"
        let written = FileTagColors.setting(["work": "blue", "home": "red"], in: markdown)
        let colors = "tag-colors:\n  home: red\n  work: blue\n"
        #expect(written == "---\ncategories:\n  - work\n" + colors + "---\n- [ ] A #work\n")
        #expect(Categories.parse(written) == ["work"])
        #expect(FileTagColors.parse(written) == ["work": "blue", "home": "red"])
        let cleared = FileTagColors.setting([:], in: written)
        #expect(cleared == "---\ncategories:\n  - work\ntag-colors:\n---\n- [ ] A #work\n")
    }

    @Test func aFileWithoutFrontmatterGetsSome() {
        let written = FileTagColors.setting(["work": "blue"], in: "- [ ] A\n")
        #expect(written == "---\ntag-colors:\n  work: blue\n---\n- [ ] A\n")
    }
}
