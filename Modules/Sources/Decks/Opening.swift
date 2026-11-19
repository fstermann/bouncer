import AppKit
import Settings

/// What one opening of the overview reads: every display's Spaces and windows, and the decks brought up
/// to date with what is open. Each display's overview then shows its own part (`Shown`).
///
/// Decks are matched over every display's windows and Spaces, so a member on another display is kept
/// rather than forgotten.
@MainActor
struct Opening {
    /// Every display's Spaces, or `nil` without SkyLight.
    let spaces: [SpaceInfo]?
    /// One item for each Space on every display, numbered for this opening.
    let items: [(item: WindowInfo, space: SpaceInfo)]
    let decks: [Deck]

    /// What one display's overview shows.
    struct Shown {
        /// The display's Spaces, or `nil` without SkyLight.
        let spaces: [SpaceInfo]?
        /// The display's windows, the current Space's first; without SkyLight, those on screen on it.
        let windows: [WindowInfo]
        /// The Space each shown window is on.
        let spaceOf: [CGWindowID: SpaceInfo]
        /// The items of the display's Spaces.
        let items: [(item: WindowInfo, space: SpaceInfo)]
    }

    /// - Parameter names: the names the user gave desktops, by Space identifier.
    static func read(decks: [Deck], names: [String: String]) -> Opening {
        let spaces = SpaceList.read()?.map { space in
            var space = space
            space.customName = names[space.uuid]
            return space
        }
        let inventory = spaces.map(SpaceItems.items(for:))
        return Opening(
            spaces: spaces,
            items: inventory ?? [],
            decks: SpaceItems.refreshed(
                decks, windows: spaces.map { SpaceList.windows(of: $0).map(\.window) } ?? WindowList.onScreen(),
                items: inventory, existing: WindowList.existing()
            )
        )
    }

    /// The part of this opening `screen` shows.
    func shown(on screen: NSScreen) -> Shown {
        guard let spaces else {
            let area = DecksController.windowServerRect(of: screen.frame)
            let windows = WindowList.onScreen().filter { area.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
            return Shown(spaces: nil, windows: windows, spaceOf: [:], items: [])
        }
        let own = SpaceList.on(display: Self.displayIdentifier(of: screen), among: spaces)
        let ids = Set(own.map(\.id))
        let listed = SpaceList.windows(of: own)
        return Shown(
            spaces: own,
            windows: listed.map(\.window),
            spaceOf: Dictionary(listed.map { ($0.window.id, $0.space) }) { first, _ in first },
            items: items.filter { ids.contains($0.space.id) }
        )
    }

    /// The display's UUID, as SkyLight names the display a Space is on.
    static func displayIdentifier(of screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
}
