import Foundation

/// A named group of windows in the window overview.
public struct Deck: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var color: DeckColor
    public var members: [DeckMember]

    public init(id: UUID = UUID(), name: String, color: DeckColor, members: [DeckMember] = []) {
        self.id = id
        self.name = name
        self.color = color
        self.members = members
    }
}

/// The colours a deck's dot can be, stored by name.
public enum DeckColor: String, Codable, CaseIterable, Sendable {
    case blue, pink, green, orange, purple, yellow, red, teal
}

/// One window of a deck.
///
/// A window's number lasts only while the window is open. The app and title are kept beside it so the
/// window is found again after its app relaunches, or the Mac restarts.
public struct DeckMember: Codable, Hashable, Sendable {
    /// The app's bundle identifier, or its name for one without.
    public var app: String
    public var title: String?
    /// `nil` while the window has not been found since it was last open.
    public var windowID: UInt32?

    public init(app: String, title: String?, windowID: UInt32?) {
        self.app = app
        self.title = title
        self.windowID = windowID
    }
}
