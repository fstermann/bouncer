import AppKit

/// Adding and removing desktops from the Spaces view, through Mission Control.
extension DecksController {
    func wireDesktops(_ session: Session) {
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
