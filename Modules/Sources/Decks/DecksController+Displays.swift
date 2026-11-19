import AppKit

/// The overviews of several displays as one: keys follow the pointer, and a window dragged onto another
/// display's overview moves to that display.
extension DecksController {
    /// The part of a display one overview covers, in AppKit's coordinates: all of it but in Dev's split.
    struct Area {
        let screen: NSScreen
        let frame: CGRect
        let visibleFrame: CGRect
    }

    public func open() {
        guard !isOpen else { return }
        open(on: NSScreen.screens.map { Area(screen: $0, frame: $0.frame, visibleFrame: $0.visibleFrame) })
    }

    /// Reports the pointer, drags and drops of `session`'s panel, handing a drag that crosses to another
    /// display over to that display's overview.
    func wirePointer(_ session: Session) {
        let overview = session.overview
        let panel = session.panel
        guard let host = panel.contentView as? PointerHost<OverviewView> else { return }
        host.onPointer = { [weak self, weak overview, weak panel] point in
            overview?.pointerMoved(to: point)
            // Keys follow the pointer, unless a name is being typed on the display that has them.
            guard let self, let panel, point != nil, !panel.isKeyWindow,
                  !sessions.contains(where: { $0.panel.isKeyWindow && $0.overview.renaming != nil })
            else { return }
            panel.makeKey()
        }
        host.onDrag = { [weak self, weak overview] point in
            overview?.dragged(to: point)
            self?.follow(dragFrom: session, at: point)
        }
        host.onRelease = { [weak self, weak overview] point in
            guard let self, let overview else { return }
            if !drop(from: session, at: point) { overview.released(at: point) }
        }
    }

    /// The session whose display holds `point`, given in `session`'s overview's coordinates.
    private func target(of point: CGPoint, from session: Session) -> (Session, CGPoint)? {
        let frame = session.area.frame
        let global = CGPoint(x: frame.minX + point.x, y: frame.maxY - point.y)
        guard let index = DisplayMove.display(at: global, among: sessions.map(\.area.frame)) else { return nil }
        let other = sessions[index]
        let local = CGPoint(x: global.x - other.area.frame.minX, y: other.area.frame.maxY - global.y)
        return (other, local)
    }

    /// Shows the dragged window on the display the pointer is over, when it is not the one it came from.
    private func follow(dragFrom session: Session, at point: CGPoint) {
        let drag = session.overview.drag.flatMap { session.overview.canMoveAcross($0) ? $0 : nil }
        let over = drag == nil ? nil : target(of: point, from: session)
        for other in sessions where other.overview !== session.overview {
            guard let drag, let over, over.0.overview === other.overview else {
                if other.overview.incoming != nil { other.overview.incoming = nil }
                continue
            }
            other.overview.incoming = Overview.Incoming(
                window: drag.window, picture: session.overview.thumbnails[drag.window.id], point: over.1
            )
        }
    }

    /// Moves the dragged window to the display the pointer let go over, if that is another one. Returns
    /// whether it did, else the drop is the source overview's own.
    private func drop(from session: Session, at point: CGPoint) -> Bool {
        for other in sessions { other.overview.incoming = nil }
        guard let drag = session.overview.drag, session.overview.canMoveAcross(drag),
              let (other, _) = target(of: point, from: session), other.overview !== session.overview,
              let moved = session.overview.endDrag()
        else { return false }
        let windows = session.overview.moved(by: moved)
        let source = Self.windowServerRect(of: session.area.visibleFrame)
        let target = Self.windowServerRect(of: other.area.visibleFrame)
        let frames = windows.map { ($0, DisplayMove.frame($0.frame, from: source, to: target)) }
        // Accessibility lists only the current Space's windows, so each other desktop is switched to first.
        let spaces = session.overview.spaces
        let bySpace = DisplayMove.bySpace(windows, spaces: spaces).map { group in
            (group.windows, group.isElsewhere ? group.windows.first.flatMap { spaces[$0.id] } : nil)
        }
        let orders = Dictionary(bySpace.compactMap(\.1).map { ($0.id, spaceOrder(of: $0)) }) { first, _ in first }
        close()
        if let front = windows.first { NSRunningApplication(processIdentifier: front.pid)?.activate() }
        Task.detached {
            for (group, space) in bySpace {
                if let space, let first = group.first {
                    await Self.switchFirst(to: space, order: orders[space.id] ?? [], raising: first)
                }
                let ids = Set(group.map(\.id))
                Tiling.apply(frames.filter { ids.contains($0.0.id) })
            }
            WindowFocus.raise(windows.reversed())
        }
        return true
    }

    /// Switches to `space`, the Space of `window`, before its windows are moved: Accessibility lists only
    /// the current Space's windows. Failing the instant switch, raising `window` slides there.
    nonisolated static func switchFirst(to space: SpaceInfo, order: [UInt64], raising window: WindowInfo) async {
        if SpaceSwitch.go(to: space.id, on: space.display, order: order) { return }
        SpaceFocus.raise(window)
        try? await Task.sleep(for: .milliseconds(400))
    }
}
