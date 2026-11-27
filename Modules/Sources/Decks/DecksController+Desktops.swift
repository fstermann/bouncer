import AppKit

/// Going to, adding and removing desktops from the Spaces view.
extension DecksController {
    func wireDesktops(_ session: Session) {
        if session.overview.hasSpaces { Self.readDesktopPictures(into: session.overview) }
        session.overview.onAddDesktop = { [weak self] in
            self?.changeDesktops(on: session.area) { await MissionControl.addDesktop(on: $0) }
        }
        session.overview.onRemoveDesktop = { [weak self] space in
            guard let place = SpaceList.position(of: space.id) else { return }
            self?.changeDesktops(on: session.area) {
                await MissionControl.removeDesktop(at: place.index, of: place.count, on: $0)
            }
        }
    }

    /// Reads each desktop's picture for its card once the overview is up, so its first frame waits for none.
    /// The current desktop falls back to the picture the overview stands on.
    private static func readDesktopPictures(into overview: Overview) {
        let desktops = overview.spaceItems.map(\.space).filter { if case .desktop = $0.kind { true } else { false } }
        let size = Metrics.card, scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        Task.detached(priority: .userInitiated) { [weak overview] in
            let pictures = Wallpaper.cardPictures(of: desktops, size: size, scale: scale)
            await MainActor.run {
                guard let overview else { return }
                var images = pictures.mapValues { NSImage(cgImage: $0, size: .zero) }
                if let current = desktops.first(where: \.isCurrent), images[current.uuid] == nil {
                    images[current.uuid] = overview.wallpaper
                }
                overview.desktopPictures = images
            }
        }
    }

    /// Goes to `desktop`, which has no window to bring forward that would take the display there.
    func switchTo(_ desktop: SpaceInfo) {
        let order = spaceOrder(of: desktop)
        close()
        Task.detached { _ = SpaceSwitch.go(to: desktop.id, on: desktop.display, order: order) }
    }

    /// Makes `change` in Mission Control on `area`'s display with the overview kept over it, then opens the
    /// overview afresh once SkyLight lists the Spaces changed, or after a second.
    private func changeDesktops(
        on area: Area, _ change: @escaping @Sendable (CGDirectDisplayID) async -> Bool
    ) {
        guard let display = (area.screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
            .uint32Value
        else { return }
        let areas = sessions.map(\.area)
        let before = SpaceList.read()?.count
        isChangingDesktops = true
        Task { [weak self] in
            if await change(display) {
                for _ in 0..<20 where SpaceList.read()?.count == before {
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
            guard let self else { return }
            isChangingDesktops = false
            // The new panels go up before the old come down, so nothing behind shows between them.
            let old = closeKeepingPanels()
            open(on: areas)
            for panel in old { panel.orderOut(nil) }
        }
    }
}
