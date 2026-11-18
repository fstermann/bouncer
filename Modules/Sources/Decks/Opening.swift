import AppKit
import Settings

/// What one opening of the overview reads: the Spaces and windows of the display it opens on, and the
/// decks brought up to date with what is open.
///
/// Decks are matched over every display's windows and Spaces, so a member on another display is kept
/// rather than forgotten; only the display's own are shown.
@MainActor
struct Opening {
    /// The display's Spaces, or `nil` without SkyLight.
    let spaces: [SpaceInfo]?
    /// The display's windows, the current Space's first; every window on screen without SkyLight.
    let windows: [WindowInfo]
    /// The Space each shown window is on.
    let spaceOf: [CGWindowID: SpaceInfo]
    /// One item for each Space on every display, numbered for this opening.
    let items: [(item: WindowInfo, space: SpaceInfo)]
    /// The items of the display's Spaces.
    let shownItems: [(item: WindowInfo, space: SpaceInfo)]
    let decks: [Deck]

    /// - Parameter names: the names the user gave desktops, by Space identifier.
    static func read(on screen: NSScreen, decks: [Deck], names: [String: String]) -> Opening {
        let everySpace = SpaceList.read()?.map { space in
            var space = space
            space.customName = names[space.uuid]
            return space
        }
        let spaces = everySpace.map { SpaceList.on(display: displayIdentifier(of: screen), among: $0) }
        let shown = Set(spaces?.map(\.id) ?? [])
        let listed = spaces.map(SpaceList.windows(of:))
        let windows = listed?.map(\.window) ?? WindowList.onScreen()
        let inventory = everySpace.map(SpaceItems.items(for:))
        let items = inventory ?? []
        return Opening(
            spaces: spaces,
            windows: windows,
            spaceOf: Dictionary(listed?.map { ($0.window.id, $0.space) } ?? []) { first, _ in first },
            items: items,
            shownItems: items.filter { shown.contains($0.space.id) },
            decks: SpaceItems.refreshed(
                decks, windows: everySpace.map { SpaceList.windows(of: $0).map(\.window) } ?? windows,
                items: inventory, existing: WindowList.existing()
            )
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
