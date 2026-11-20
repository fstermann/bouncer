import Foundation

/// A named group in the window overview: of windows, or of Spaces.
public struct Deck: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    /// The SF Symbol on the deck's badge; `nil` until the user picks one.
    public var symbol: String?
    /// Which of the overview's two views the deck belongs to.
    public var kind: DeckKind
    public var members: [DeckMember]

    public init(
        id: UUID = UUID(), name: String, symbol: String? = nil, kind: DeckKind = .windows, members: [DeckMember] = []
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.kind = kind
        self.members = members
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
        kind = try container.decodeIfPresent(DeckKind.self, forKey: .kind) ?? .windows
        members = try container.decode([DeckMember].self, forKey: .members)
    }
}

/// The overview's two levels: windows, from every Space, and the Spaces themselves.
public enum DeckKind: String, Codable, CaseIterable, Sendable {
    case windows, spaces
}

/// One window, or one Space, of a deck.
///
/// A window's number lasts only while the window is open. The app and title are kept beside it so the
/// window is found again after its app relaunches, or the Mac restarts. A full screen app's Space is
/// stored as its window, since the Space goes when the app leaves full screen; a desktop by its
/// Space's identifier, which lasts until the desktop is removed.
public struct DeckMember: Codable, Hashable, Sendable {
    /// The app's bundle identifier, or its name for one without; empty for a desktop.
    public var app: String
    public var title: String?
    /// `nil` while the window has not been found since it was last open.
    public var windowID: UInt32?
    /// The desktop's Space identifier, for a desktop.
    public var space: String?

    public init(app: String, title: String?, windowID: UInt32?, space: String? = nil) {
        self.app = app
        self.title = title
        self.windowID = windowID
        self.space = space
    }
}
