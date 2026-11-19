import AppKit

/// Narrows the overview's cards to what the user types.
enum OverviewFilter {
    /// `arrangement` with only the items whose title or app holds `query`, ignoring case and accents.
    /// A deck whose name holds it keeps every item; any other keeps its matching items, or goes.
    ///
    /// - Parameter contents: the windows an item stands for, so a desktop matches by its windows too.
    static func filtered(
        _ arrangement: Arrangement, by query: String, contents: (WindowInfo) -> [WindowInfo] = { _ in [] }
    ) -> Arrangement {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return arrangement }
        func matches(_ item: WindowInfo) -> Bool {
            ([item] + contents(item)).contains {
                $0.label.localizedStandardContains(query) || $0.appName.localizedStandardContains(query)
            }
        }
        let decks = arrangement.decks.compactMap { live -> LiveDeck? in
            if live.deck.name.localizedStandardContains(query) { return live }
            let windows = live.windows.filter(matches)
            return windows.isEmpty ? nil : LiveDeck(deck: live.deck, windows: windows)
        }
        return Arrangement(decks: decks, ungrouped: arrangement.ungrouped.filter(matches))
    }
}

/// The keys the overview acts on, read from key presses the panel did not hand a text field.
enum OverviewKey: Equatable {
    case rename
    case escape
    case delete
    case enter
    case text(String)

    init?(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        switch event.keyCode {
        case 53: self = .escape
        case 51: self = .delete
        case 36, 76: self = .enter
        default:
            if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "r" {
                self = .rename
                return
            }
            guard modifiers.isDisjoint(with: [.command, .control]), let text = event.characters,
                  !text.isEmpty, text.unicodeScalars.allSatisfy(Self.isTyped)
            else { return nil }
            self = .text(text)
        }
    }

    /// Whether `scalar` is text, not a control character or the private use code AppKit gives arrow keys.
    private static func isTyped(_ scalar: Unicode.Scalar) -> Bool {
        !scalar.properties.generalCategory.isControlOrPrivate
    }
}

private extension Unicode.GeneralCategory {
    var isControlOrPrivate: Bool {
        self == .control || self == .privateUse || self == .format || self == .unassigned
    }
}
