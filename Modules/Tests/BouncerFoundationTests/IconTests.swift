import Testing

@testable import BouncerFoundation

@Suite struct IconTests {
    @Test func everyIconIsInTheCatalog() {
        let missing = Icon.allCases.filter { $0.nsImage() == nil }
        #expect(missing.isEmpty, "Run Tools/icons.sh: \(missing)")
    }

    @Test func iconsLoadAsSymbols() {
        #expect(Icon.close.nsImage()?.isTemplate == true)
    }
}
