import AppKit

/// One of the user's Spaces: a desktop, or a full screen app's own Space.
public struct SpaceInfo: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// The desktop's place among its display's desktops, from 1, as Mission Control numbers them.
        case desktop(number: Int)
        case fullScreen
    }

    /// The window server's number for the Space, stable only while it exists.
    public let id: UInt64
    /// Lasts as long as the Space does, across restarts.
    public let uuid: String
    public let kind: Kind
    public let isCurrent: Bool
    /// Its ordinary windows, front to back.
    public let windows: [WindowInfo]
    /// SkyLight's identifier of the display the Space is on: its UUID, or "Main" while displays share Spaces.
    public var display = ""
    /// The name the user gave a desktop in the overview.
    public var customName: String?
}

extension SpaceInfo {
    /// What the overview calls the Space: "Desktop 2", or the full screen app's window.
    public var name: String {
        switch kind {
        case .desktop(let number): customName ?? "Desktop \(number)"
        case .fullScreen: windows.first?.appName ?? "Full screen"
        }
    }
}

/// Reads the Spaces and the windows on each through SkyLight, the window server's private framework.
///
/// No public API lists Spaces, or the windows on a Space other than the current one. The calls are
/// resolved at runtime: if a release drops one, `read` returns `nil` and the overview shows only the
/// current Space's windows, as the public window list does.
enum SpaceList {
    /// The Spaces on the display `display`, or all of them when none is, as while displays share Spaces.
    static func on(display: String?, among spaces: [SpaceInfo]) -> [SpaceInfo] {
        let own = spaces.filter { $0.display == display }
        return own.isEmpty ? spaces : own
    }

    /// Every Space on every display in Mission Control's order, with its windows.
    @MainActor static func read() -> [SpaceInfo]? {
        guard let sky = SkyLight.shared,
              let displays = sky.displaySpaces(sky.connection)?.takeRetainedValue() as? [[String: Any]]
        else { return nil }
        let entries = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let windows = WindowList.windows(in: entries, excluding: ProcessInfo.processInfo.processIdentifier) {
            NSRunningApplication(processIdentifier: $0)?.bundleIdentifier
        }
        let spaces = displays.flatMap { $0["Spaces"] as? [[String: Any]] ?? [] }
        var onSpace: [UInt64: [CGWindowID]] = [:]
        for space in spaces {
            guard let id = (space["ManagedSpaceID"] as? NSNumber)?.uint64Value else { continue }
            onSpace[id] = sky.ordinaryWindows(on: id)
        }
        return assemble(displays: displays, windowsOnSpace: onSpace, windows: windows)
    }

    /// Every window on every Space, the current Space's first, then by Space in Mission Control's order,
    /// each paired with the Space it is on.
    static func windows(of spaces: [SpaceInfo]) -> [(window: WindowInfo, space: SpaceInfo)] {
        let ordered = spaces.filter(\.isCurrent) + spaces.filter { !$0.isCurrent }
        var seen = Set<CGWindowID>()
        return ordered.flatMap { space in
            space.windows.compactMap { window in seen.insert(window.id).inserted ? (window, space) : nil }
        }
    }

    /// Pairs the display list SkyLight returns with the windows found on each Space.
    ///
    /// Desktops and full screen Spaces are kept; a full screen Space without a window of its own is not
    /// a place anyone can go back to, so it is left out.
    static func assemble(
        displays: [[String: Any]], windowsOnSpace: [UInt64: [CGWindowID]], windows: [WindowInfo]
    ) -> [SpaceInfo] {
        let byID = Dictionary(windows.map { ($0.id, $0) }) { first, _ in first }
        return displays.flatMap { display -> [SpaceInfo] in
            let identifier = display["Display Identifier"] as? String ?? ""
            let current = ((display["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? NSNumber)?.uint64Value
            var desktops = 0
            return (display["Spaces"] as? [[String: Any]] ?? []).compactMap { space in
                guard let id = (space["ManagedSpaceID"] as? NSNumber)?.uint64Value,
                      let uuid = space["uuid"] as? String,
                      let type = (space["type"] as? NSNumber)?.intValue
                else { return nil }
                let found = (windowsOnSpace[id] ?? []).compactMap { byID[$0] }
                let kind: SpaceInfo.Kind
                switch type {
                case desktopType:
                    desktops += 1
                    kind = .desktop(number: desktops)
                case fullScreenType where !found.isEmpty:
                    kind = .fullScreen
                default:
                    return nil
                }
                return SpaceInfo(
                    id: id, uuid: uuid, kind: kind, isCurrent: id == current, windows: found, display: identifier
                )
            }
        }
    }

    /// SkyLight's space types: 0 a desktop, 4 a full screen app's Space.
    static let desktopType = 0
    static let fullScreenType = 4

    /// Whether a window the window server lists on a Space is one the user put there.
    ///
    /// Apps keep many windows the user never sees: toolbars of full screen apps, ordered out helpers.
    /// Apple documents none of these bits; they were checked against every window on a Mac with 20 Spaces.
    static func isOrdinary(parent: UInt32, level: Int32, attributes: UInt64, tags: UInt64) -> Bool {
        guard parent == 0, level == 0 else { return false }
        let visible = attributes & 0x2 != 0 || tags & 0x0400_0000_0000_0000 != 0
        let document = tags & 0x1 != 0 || (tags & 0x2 != 0 && tags & 0x8000_0000 != 0)
        return visible && document
    }
}

/// The SkyLight calls the overview uses, resolved once.
private struct SkyLight {
    typealias Connection = @convention(c) () -> Int32
    typealias DisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    typealias WindowsOnSpaces = @convention(c) (
        Int32, UInt32, CFArray, UInt32, UnsafeMutablePointer<UInt64>, UnsafeMutablePointer<UInt64>
    ) -> Unmanaged<CFArray>?
    typealias Query = @convention(c) (Int32, CFArray, Int32) -> Unmanaged<CFTypeRef>?
    typealias Results = @convention(c) (CFTypeRef) -> Unmanaged<CFTypeRef>?
    typealias Advance = @convention(c) (CFTypeRef) -> Bool
    typealias Number = @convention(c) (CFTypeRef) -> UInt32
    typealias Bits = @convention(c) (CFTypeRef) -> UInt64
    typealias Level = @convention(c) (CFTypeRef) -> Int32

    let connection: Int32
    let displaySpaces: DisplaySpaces
    let windowsOnSpaces: WindowsOnSpaces
    let query: Query
    let results: Results
    let advance: Advance
    let windowID: Number
    let parentID: Number
    let tags: Bits
    let attributes: Bits
    let level: Level

    @MainActor static let shared: SkyLight? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) else {
            return nil
        }
        func load<T>(_ name: String, as _: T.Type) -> T? {
            dlsym(handle, name).map { unsafeBitCast($0, to: T.self) }
        }
        guard let connection = load("SLSMainConnectionID", as: Connection.self),
              let displaySpaces = load("SLSCopyManagedDisplaySpaces", as: DisplaySpaces.self),
              let windowsOnSpaces = load("SLSCopyWindowsWithOptionsAndTags", as: WindowsOnSpaces.self),
              let query = load("SLSWindowQueryWindows", as: Query.self),
              let results = load("SLSWindowQueryResultCopyWindows", as: Results.self),
              let advance = load("SLSWindowIteratorAdvance", as: Advance.self),
              let windowID = load("SLSWindowIteratorGetWindowID", as: Number.self),
              let parentID = load("SLSWindowIteratorGetParentID", as: Number.self),
              let tags = load("SLSWindowIteratorGetTags", as: Bits.self),
              let attributes = load("SLSWindowIteratorGetAttributes", as: Bits.self),
              let level = load("SLSWindowIteratorGetLevel", as: Level.self)
        else { return nil }
        return SkyLight(
            connection: connection(), displaySpaces: displaySpaces, windowsOnSpaces: windowsOnSpaces,
            query: query, results: results, advance: advance, windowID: windowID, parentID: parentID,
            tags: tags, attributes: attributes, level: level
        )
    }()

    /// The ordinary windows on `space`, front to back. Minimized windows are left out, as on screen.
    func ordinaryWindows(on space: UInt64) -> [CGWindowID] {
        var setTags: UInt64 = 0
        var clearTags: UInt64 = 0
        // 0x2: windows on the Space, minimized ones not among them.
        guard let list = windowsOnSpaces(connection, 0, [space] as CFArray, 0x2, &setTags, &clearTags)?
                .takeRetainedValue(),
              let query = query(connection, list, 0)?.takeRetainedValue(),
              let iterator = results(query)?.takeRetainedValue()
        else { return [] }
        var found: [CGWindowID] = []
        while advance(iterator) {
            guard SpaceList.isOrdinary(
                parent: parentID(iterator), level: level(iterator),
                attributes: attributes(iterator), tags: tags(iterator)
            ) else { continue }
            found.append(windowID(iterator))
        }
        return found
    }
}
