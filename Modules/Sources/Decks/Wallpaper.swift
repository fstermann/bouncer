import AppKit

/// The desktop picture the overview blurs behind its cards.
///
/// AppKit names the current Space's picture only, and on a full screen Space, which has none, it names
/// the system default. The wallpaper agent records each desktop's choice in its store, so a full screen
/// Space shows its display's first desktop's picture from there.
enum Wallpaper {
    static let store = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")

    /// The picture for the overview on `screen`, whose Spaces are `spaces` (all displays' when unknown).
    @MainActor static func image(for screen: NSScreen, spaces: [SpaceInfo]?) -> NSImage? {
        let url = fullScreenDesktop(among: spaces).flatMap { desktop in
            (NSDictionary(contentsOf: store) as? [String: Any]).flatMap {
                imageURL(in: $0, space: desktop.uuid, display: desktop.display)
            }
        } ?? NSWorkspace.shared.desktopImageURL(for: screen)
        return url.flatMap(NSImage.init(contentsOf:))
    }

    /// The first desktop of `spaces` when the current one of them is a full screen app's, else `nil`.
    static func fullScreenDesktop(among spaces: [SpaceInfo]?) -> SpaceInfo? {
        guard let spaces, spaces.first(where: \.isCurrent)?.kind == .fullScreen else { return nil }
        return spaces.first { if case .desktop = $0.kind { true } else { false } }
    }

    /// The image file the store records for the desktop `space` on `display`. `nil` for a colour, a
    /// dynamic or aerial picture, or a Space the store does not know.
    static func imageURL(in store: [String: Any], space: String, display: String) -> URL? {
        guard let entry = (store["Spaces"] as? [String: Any])?[space] as? [String: Any] else { return nil }
        let chosen = ((entry["Displays"] as? [String: Any])?[display] ?? entry["Default"]) as? [String: Any]
        guard let content = (chosen?["Desktop"] as? [String: Any])?["Content"] as? [String: Any],
              let choice = (content["Choices"] as? [[String: Any]])?.first,
              choice["Provider"] as? String == "com.apple.wallpaper.choice.image",
              let data = choice["Configuration"] as? Data,
              let configuration = try? PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any],
              let relative = (configuration["url"] as? [String: Any])?["relative"] as? String
        else { return nil }
        return URL(string: relative)
    }
}
