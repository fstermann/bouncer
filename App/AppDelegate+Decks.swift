import Decks

extension AppDelegate {
    /// The window overview, and in Bouncer Dev the harness command that opens and closes it.
    func wireDecks() {
        decks.start()
        #if DEV
        harness?.commands["decks"] = { [decks, settings] words in
            switch words.first {
            case "on", "off":
                settings.preferences.enableDecks = words.first == "on"
                return "decks \(words[0])"
            default:
                decks.toggle()
                return decks.isOpen ? "opened" : "closed"
            }
        }
        #endif
    }
}
