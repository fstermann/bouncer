import Foundation
import Testing

@testable import Settings

@Suite struct DeckTests {
    @Test func loadsADeckSavedWithAColourAndNoSymbol() throws {
        let saved = #"{"id":"7C9E6679-7425-40DE-944B-E07FC1F90AE7","name":"Work","color":"teal","members":[]}"#
        let deck = try JSONDecoder().decode(Deck.self, from: Data(saved.utf8))
        #expect(deck.symbol == nil)
        #expect(deck.kind == .windows)
    }

    @Test func keepsThePickedSymbol() throws {
        let deck = Deck(name: "Work", symbol: "star.fill")
        let decoded = try JSONDecoder().decode(Deck.self, from: JSONEncoder().encode(deck))
        #expect(decoded.symbol == "star.fill")
    }
}
