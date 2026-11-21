import AppKit

/// The desktop picture the overview blurs behind its cards.
///
/// The Dock draws each desktop's picture in a window of its own, "Wallpaper-<Space UUID>", so the
/// picture is captured from there, whatever its source; on a full screen Space, which has none, from the
/// display's first desktop. AppKit names the system default for some displays and Spaces, so without a
/// capture the wallpaper agent's store is read for a full screen Space, and AppKit otherwise.
enum Wallpaper {
    static let store = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")

    /// The picture for the overview on `screen`, whose Spaces are `spaces` (all displays' when unknown).
    @MainActor static func image(for screen: NSScreen, spaces: [SpaceInfo]?) -> NSImage? {
        if let desktop = shownDesktop(among: spaces),
           let entries = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]],
           let window = dockWindow(of: desktop.uuid, in: entries),
           let image = WindowCapture.image(of: window) {
            return NSImage(cgImage: image, size: .zero)
        }
        let url = fullScreenDesktop(among: spaces).flatMap { desktop in
            (NSDictionary(contentsOf: store) as? [String: Any]).flatMap {
                imageURL(in: $0, space: desktop.uuid, display: desktop.display)
            }
        } ?? NSWorkspace.shared.desktopImageURL(for: screen)
        return url.flatMap { picture(at: $0, for: screen) }
    }

    private struct Decoded {
        let url: URL, changed: Date?, size: CGFloat, image: NSImage
    }
    @MainActor private static var decoded: Decoded?

    /// The picture at `url`, decoded at `screen`'s size in points and kept until it changes. The overview
    /// blurs it by 28 pt, which leaves nothing a sharper copy would show, and decoding the whole picture
    /// held up the overview's first frame on every open.
    @MainActor private static func picture(at url: URL, for screen: NSScreen) -> NSImage? {
        let changed = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let size = max(screen.frame.width, screen.frame.height)
        if let decoded, decoded.url == url, decoded.changed == changed, decoded.size == size { return decoded.image }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: size
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let picture = CGImageSourceCreateThumbnailAtIndex(source, 0, options)
        else { return nil }
        let image = NSImage(cgImage: picture, size: .zero)
        decoded = Decoded(url: url, changed: changed, size: size, image: image)
        return image
    }

    /// The desktop whose picture stands behind `spaces`: the current one, or the first when a full screen
    /// app's is current.
    static func shownDesktop(among spaces: [SpaceInfo]?) -> SpaceInfo? {
        guard let current = spaces?.first(where: \.isCurrent) else { return nil }
        return current.kind == .fullScreen ? fullScreenDesktop(among: spaces) : current
    }

    /// The Dock's window drawing the picture of the desktop `space`, from the window list's `entries`.
    static func dockWindow(of space: String, in entries: [[String: Any]]) -> CGWindowID? {
        let name = "Wallpaper-\(space)"
        let entry = entries.first {
            $0[kCGWindowOwnerName as String] as? String == "Dock" && $0[kCGWindowName as String] as? String == name
        }
        return (entry?[kCGWindowNumber as String] as? NSNumber)?.uint32Value
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
