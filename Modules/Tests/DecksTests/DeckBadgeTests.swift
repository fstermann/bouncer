import AppKit
import Settings
import Testing

@testable import Decks

@Suite struct DeckBadgeTests {
    private func window(_ id: CGWindowID, app: String) -> WindowInfo {
        WindowInfo(id: id, pid: 1, bundleID: app, appName: app, title: nil, frame: .zero)
    }

    @Test func keepsOneWindowPerAppInFirstSeenOrder() {
        let windows = [
            window(1, app: "code"), window(2, app: "chrome"), window(3, app: "code"), window(4, app: "slack")
        ]
        #expect(DeckApps.distinct(windows).map(\.id) == [1, 2, 4])
    }

    @Test func everySymbolChoiceExistsOnThisMacOS() {
        let missing = DeckSymbols.choices.filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil }
        #expect(missing.isEmpty)
        #expect(Set(DeckSymbols.choices).count == DeckSymbols.choices.count)
    }

    @Test func showsTheFallbackUntilOneIsPicked() {
        var deck = Deck(name: "Work")
        #expect(DeckSymbols.symbol(of: deck) == DeckSymbols.fallback)
        deck.symbol = "star.fill"
        #expect(DeckSymbols.symbol(of: deck) == "star.fill")
    }
}
