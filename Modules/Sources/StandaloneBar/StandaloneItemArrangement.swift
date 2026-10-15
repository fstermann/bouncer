import AppKit
import CoreGraphics
import MenuBar
import Observation
import Settings

/// The standalone items as an editable settings preview.
///
/// The preview is never persisted as a second order. A drop synthesises macOS's own
/// Command-drag between the two real status-item windows; macOS stores that order, and a fresh
/// scan replaces the preview after the menu bar has settled.
@MainActor
@Observable
public final class StandaloneItemArrangement {
    public private(set) var items: [MenuBarItem] = []
    public private(set) var isApplying = false
    public var images: [UInt32: CGImage] { capture.images }

    @ObservationIgnored private let menuBar: MenuBarManager
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let capture = ItemCapture()
    @ObservationIgnored private let cover = CoverWindow()
    @ObservationIgnored private var orderBeforePreview: [MenuBarItem]?
    @ObservationIgnored private var applying: Task<Void, Never>?

    public init(menuBar: MenuBarManager, settings: SettingsStore) {
        self.menuBar = menuBar
        self.settings = settings
    }

    public func refresh() {
        guard !isApplying, ItemCapture.isAvailable else { return }
        isApplying = true
        applying?.cancel()
        applying = Task { [weak self] in await self?.refreshNow() }
    }

    private func refreshNow() async {
        defer { isApplying = false }
        let screens = NSScreen.screens.map(\.frame)
        for attempt in 0...8 {
            let own = StatusItemScanner.bouncersOwn()
            let all = StatusItemScanner.scan()
            guard let found = Self.previewItems(from: all, own: own, screens: screens) else {
                guard attempt < 8 else { return }
                try? await Task.sleep(for: .milliseconds(250))
                if Task.isCancelled { return }
                continue
            }

            // Discovery and photography are separate outcomes. Keep the replicas visible even
            // if WindowServer cannot provide their pixels on this attempt.
            items = found

            switch Self.capturePlan(
                for: found,
                existingImageIDs: Set(capture.images.keys),
                screens: screens
            ) {
            case .reuse:
                break
            case .captureWhereTheyAre:
                capture.capture(found)
            case .revealThenCapture:
                await captureHidden(found, among: all)
            }
            return
        }
    }

    enum CapturePlan: Equatable {
        case reuse
        case captureWhereTheyAre
        case revealThenCapture
    }

    static func capturePlan(
        for items: [MenuBarItem], existingImageIDs: Set<UInt32>, screens: [CGRect]
    ) -> CapturePlan {
        let ids = Set(items.map(\.windowID))
        if ids.isSubset(of: existingImageIDs) { return .reuse }
        return MenuBarItemGeometry.offScreen(items, screens: screens).isEmpty
            ? .captureWhereTheyAre
            : .revealThenCapture
    }

    private func captureHidden(_ parked: [MenuBarItem], among all: [MenuBarItem]) async {
        let ids = Set(parked.map(\.windowID))
        items = parked
        guard !ids.isEmpty, menuBar.visibility == .collapsed else {
            capture.capture(parked)
            return
        }

        let real = MenuBarItemGeometry.excludingDividers(all)
        let landing = MenuBarItemGeometry.landingStrip(for: parked, leftOf: real)
        cover.style = settings.preferences.barStyle
        cover.show(over: landing.insetBy(dx: -ReplicaBar.padding, dy: 0))

        let wasHeld = menuBar.isRevealHeld
        menuBar.isRevealHeld = true
        menuBar.setBoundaryMarkersVisible(false)
        menuBar.setVisibility(.revealed)
        // A frame can have reached its final coordinate before WindowServer has drawn its
        // backing surface there. Give the revealed items a short render turn, then require
        // the divider-defined section itself to settle before photographing it. Its window IDs
        // are deliberately not carried across the reveal: WindowServer may renumber them.
        try? await Task.sleep(for: .milliseconds(150))

        let revealed = await stableCaptureCandidates(
            expectedCount: parked.count, screens: NSScreen.screens.map(\.frame)
        )
        if let revealed {
            items = revealed
            if let strip = MenuBarItemGeometry.coverRect(for: revealed) {
                cover.show(over: strip.insetBy(dx: -ReplicaBar.padding, dy: 0))
            }
            // Window frames can settle before their backing surfaces contain pixels. Keep the
            // section covered and retry only while this user-requested refresh is active.
            for _ in 0..<10 {
                if capture.capture(revealed) { break }
                try? await Task.sleep(for: .milliseconds(50))
                if Task.isCancelled { break }
            }
        }

        let idsToHide = Set((revealed ?? parked).map(\.windowID))
        menuBar.setVisibility(.collapsed)
        await PlacementWait.removal(of: idsToHide)
        menuBar.setBoundaryMarkersVisible(true)
        menuBar.isRevealHeld = wasHeld
        cover.hide()
    }

    private func stableCaptureCandidates(
        expectedCount: Int, screens: [CGRect]
    ) async -> [MenuBarItem]? {
        var previous: [MenuBarItem]?
        var matchingReadings = 0
        for _ in 0..<30 {
            let current = Self.captureCandidates(
                from: StatusItemScanner.scan(),
                own: StatusItemScanner.bouncersOwn(),
                expectedCount: expectedCount,
                screens: screens
            )
            matchingReadings = current != nil && current == previous ? matchingReadings + 1 : 1
            previous = current
            if matchingReadings >= 6, let current { return current }
            try? await Task.sleep(for: .milliseconds(16))
            if Task.isCancelled { return nil }
        }
        return nil
    }

    static func captureCandidates(
        from all: [MenuBarItem],
        own: [UInt32: String],
        expectedCount: Int,
        screens: [CGRect]
    ) -> [MenuBarItem]? {
        guard let found = previewItems(from: all, own: own, screens: screens),
              found.count == expectedCount,
              MenuBarItemGeometry.offScreen(found, screens: screens).isEmpty
        else { return nil }
        return found
    }

    static func previewItems(
        from all: [MenuBarItem], own: [UInt32: String], screens: [CGRect]
    ) -> [MenuBarItem]? {
        let real = MenuBarItemGeometry.excludingDividers(all)
            .filter { own[$0.windowID] == nil }
        let parked = MenuBarItemGeometry.offScreen(real, screens: screens)
        guard let dividerID = own.first(where: { $0.value == StatusItemPosition.hiddenDividerName })?.key,
              let divider = all.first(where: { $0.windowID == dividerID })
        else { return nil }
        guard divider.frame.width < MenuBarItemGeometry.dividerWidthThreshold else { return parked }
        let onScreen = real.filter { item in
            screens.contains { $0.minX...$0.maxX ~= item.frame.midX }
        }
        return MenuBarItemGeometry.section(onScreen, leftOf: divider.frame.minX)
    }

    public func beginPreview() {
        guard !isApplying else { return }
        orderBeforePreview = items
    }

    public func previewMove(_ item: UInt32, over destination: UInt32) {
        guard !isApplying,
              item != destination,
              let sourceIndex = items.firstIndex(where: { $0.windowID == item }),
              let destinationIndex = items.firstIndex(where: { $0.windowID == destination })
        else { return }
        let moved = items.remove(at: sourceIndex)
        items.insert(moved, at: destinationIndex)
    }

    public func commitPreview(of item: UInt32) {
        guard !isApplying, let originalOrder = orderBeforePreview,
              let destination = Self.destination(for: item, in: items)
        else {
            orderBeforePreview = nil
            return
        }
        orderBeforePreview = nil
        isApplying = true
        applying?.cancel()
        applying = Task { [weak self] in
            guard let self else { return }
            let desiredOrder = items
            let settled = await move(item, to: destination, expecting: desiredOrder)
            guard !Task.isCancelled else { return }
            items = settled ?? originalOrder
            isApplying = false
        }
    }

    private func move(
        _ item: UInt32, to destination: Destination, expecting desiredOrder: [MenuBarItem]
    ) async -> [MenuBarItem]? {
        let originalIDs = Set(desiredOrder.map(\.windowID))
        let screens = NSScreen.screens.map(\.frame)
        let before = StatusItemScanner.scan()
        let current = before.filter { originalIDs.contains($0.windowID) }
        let needsReveal = Self.requiresRevealForMove(current, screens: screens)
        let wasHeld = menuBar.isRevealHeld

        if needsReveal {
            guard menuBar.visibility == .collapsed else { return nil }
            let real = MenuBarItemGeometry.excludingDividers(before)
            let landing = MenuBarItemGeometry.landingStrip(for: current, leftOf: real)
            cover.style = settings.preferences.barStyle
            cover.show(over: landing.insetBy(dx: -ReplicaBar.padding, dy: 0))
            menuBar.isRevealHeld = true
            menuBar.setBoundaryMarkersVisible(false)
            menuBar.setVisibility(.revealed)
            await PlacementWait.placement(of: originalIDs)
        }

        let didPostMove = await StatusItemMover.move(item, to: destination)
        // A status-item drop starts quickly but can keep rearranging the bar for 410 ms.
        // Reading before that completes reports the order from before the drop.
        if didPostMove { try? await Task.sleep(for: .milliseconds(450)) }

        let all = StatusItemScanner.scan()
        let own = StatusItemScanner.bouncersOwn()
        let found = Self.previewItems(from: all, own: own, screens: screens)
        let settled = didPostMove ? Self.verified(found, matches: desiredOrder) : nil

        // The first system drag can renumber status-item windows. Refresh their snapshots while
        // they are already revealed and covered, instead of showing question marks afterwards.
        if let settled {
            let settledIDs = Set(settled.map(\.windowID))
            if !settledIDs.isSubset(of: Set(capture.images.keys)) { capture.capture(settled) }
        }

        if needsReveal {
            let idsToHide = Set((settled ?? current).map(\.windowID))
            menuBar.setVisibility(.collapsed)
            await PlacementWait.removal(of: idsToHide)
            menuBar.setBoundaryMarkersVisible(true)
            menuBar.isRevealHeld = wasHeld
            cover.hide()
        }
        return settled
    }

    static func requiresRevealForMove(_ items: [MenuBarItem], screens: [CGRect]) -> Bool {
        !MenuBarItemGeometry.offScreen(items, screens: screens).isEmpty
    }

    static func verified(
        _ found: [MenuBarItem]?, matches desiredOrder: [MenuBarItem]
    ) -> [MenuBarItem]? {
        guard let found, found.count == desiredOrder.count else { return nil }
        let foundIDs = found.map(\.windowID)
        let desiredIDs = desiredOrder.map(\.windowID)
        // If WindowServer retained the IDs, it can prove the exact order. When it renumbers
        // them, equal membership is unknowable; the completed system gesture is the authority.
        if Set(foundIDs) == Set(desiredIDs), foundIDs != desiredIDs { return nil }
        return found
    }

    enum Destination: Equatable {
        case before(UInt32)
        case after(UInt32)
    }

    static func destination(for item: UInt32, in order: [MenuBarItem]) -> Destination? {
        guard let index = order.firstIndex(where: { $0.windowID == item }) else { return nil }
        if order.indices.contains(index + 1) { return .before(order[index + 1].windowID) }
        if index > order.startIndex { return .after(order[index - 1].windowID) }
        return nil
    }
}
