import Foundation
import Testing

@testable import BouncerFoundation

/// Checks the catalog's sources, not the compiled images: `swift test` on the native build system
/// copies an asset catalog without compiling it, so `Bundle.module` finds no symbols there.
@Suite struct IconTests {
    private let catalog = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/BouncerFoundation/Resources/Icons.xcassets")

    @Test func everyIconIsInTheCatalog() {
        let missing = Icon.allCases.filter {
            let svg = catalog.appendingPathComponent("\($0.rawValue).symbolset/\($0.rawValue).svg")
            return !FileManager.default.fileExists(atPath: svg.path)
        }
        #expect(missing.isEmpty, "Run Tools/icons.sh: \(missing)")
    }

    @Test func catalogHoldsNoIconOutsideTheList() throws {
        let sets = try FileManager.default.contentsOfDirectory(atPath: catalog.path)
            .filter { $0.hasSuffix(".symbolset") }
        let unlisted = sets.map { String($0.dropLast(".symbolset".count)) }.filter { Icon(rawValue: $0) == nil }
        #expect(unlisted.isEmpty, "\(unlisted)")
    }
}
