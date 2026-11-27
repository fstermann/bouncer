import AppKit

/// The desktop picture the overview blurs behind its cards.
///
/// Each desktop's picture is drawn in a window of its own, so the picture is captured from there, whatever
/// its source; on a full screen Space, which has none, from the display's first desktop. Up to macOS 26
/// the Dock draws it in "Wallpaper-<Space UUID>"; from macOS 27 WindowManager draws it in windows all
/// named "Wallpaper", told apart by the Space SkyLight puts each on. AppKit names the system default for
/// some displays and Spaces, so without a capture the wallpaper agent's store is read for a full screen
/// Space, and AppKit otherwise.
enum Wallpaper {
    static let store = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")

    /// The picture for the overview on `screen`, whose Spaces are `spaces` (all displays' when unknown).
    @MainActor static func image(for screen: NSScreen, spaces: [SpaceInfo]?) -> NSImage? {
        if let desktop = shownDesktop(among: spaces),
           let entries = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]],
           let window = window(of: desktop, in: entries),
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

    /// The window drawing the picture of the desktop `space`, from the window list's `entries`.
    static func window(of space: SpaceInfo, in entries: [[String: Any]]) -> CGWindowID? {
        dockWindow(of: space.uuid, in: entries)
            ?? windowManagerWallpapers(in: entries).first { WallpaperSpaces.of($0).contains(space.id) }
    }

    /// The windows macOS 27's WindowManager draws desktop pictures in, from the window list's `entries`.
    static func windowManagerWallpapers(in entries: [[String: Any]]) -> [CGWindowID] {
        entries.compactMap { entry in
            guard entry[kCGWindowOwnerName as String] as? String == "WindowManager",
                  entry[kCGWindowName as String] as? String == "Wallpaper"
            else { return nil }
            return (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value
        }
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

    /// The image file the store records for the desktop `space` on `display`, or for all Spaces when it
    /// has none of its own. `nil` for a colour or a dynamic or aerial picture.
    static func imageURL(in store: [String: Any], space: String, display: String) -> URL? {
        let entry = (store["Spaces"] as? [String: Any])?[space] as? [String: Any]
        let own = entry.flatMap { ($0["Displays"] as? [String: Any])?[display] ?? $0["Default"] }
        let chosen = (own ?? store["AllSpacesAndDisplays"]) as? [String: Any]
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

    /// Each desktop of `spaces`' picture, by Space UUID, sized to fill a card `size` pt at `scale`: captured
    /// from its window, else the image file the store records. A desktop with neither is left out.
    static func cardPictures(of spaces: [SpaceInfo], size: CGSize, scale: CGFloat) -> [String: CGImage] {
        let entries = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        let store = NSDictionary(contentsOf: Self.store) as? [String: Any]
        let pixels = CGSize(width: size.width * scale, height: size.height * scale)
        var pictures: [String: CGImage] = [:]
        for space in spaces {
            if let window = window(of: space, in: entries), let image = WindowCapture.image(of: window) {
                pictures[space.uuid] = shrunk(image, toFill: pixels) ?? image
            } else if let url = store.flatMap({ imageURL(in: $0, space: space.uuid, display: space.display) }) {
                pictures[space.uuid] = thumbnail(at: url, longestSide: 2 * max(pixels.width, pixels.height))
            }
        }
        return pictures
    }

    private static func thumbnail(at url: URL, longestSide: CGFloat) -> CGImage? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: longestSide
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }

    /// `image` scaled down, keeping its shape, to the smallest size that still covers `size` pixels.
    private static func shrunk(_ image: CGImage, toFill size: CGSize) -> CGImage? {
        let factor = max(size.width / CGFloat(image.width), size.height / CGFloat(image.height))
        guard factor < 1 else { return image }
        let width = Int((CGFloat(image.width) * factor).rounded(.up))
        let height = Int((CGFloat(image.height) * factor).rounded(.up))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

/// The Spaces SkyLight puts a window on.
private enum WallpaperSpaces {
    private typealias Copy = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?

    private struct Calls: @unchecked Sendable {
        let connection: Int32
        let copy: Copy
    }

    private static let calls: Calls? = {
        guard let sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let connection = dlsym(sky, "SLSMainConnectionID"),
              let copy = dlsym(sky, "SLSCopySpacesForWindows")
        else { return nil }
        let main = unsafeBitCast(connection, to: (@convention(c) () -> Int32).self)
        return Calls(connection: main(), copy: unsafeBitCast(copy, to: Copy.self))
    }()

    static func of(_ window: CGWindowID) -> [UInt64] {
        guard let calls else { return [] }
        // 7: every kind of Space, current or not.
        let spaces = calls.copy(calls.connection, 7, [NSNumber(value: window)] as CFArray)?.takeRetainedValue()
        return (spaces as? [NSNumber])?.map(\.uint64Value) ?? []
    }
}
