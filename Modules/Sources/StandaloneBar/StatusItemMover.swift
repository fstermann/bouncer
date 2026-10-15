import AppKit
import CoreGraphics

@MainActor
enum StatusItemMover {
    static func move(
        _ itemID: UInt32, to destination: StandaloneItemArrangement.Destination
    ) async -> Bool {
        // Let AppKit finish the settings drag before starting a second, synthetic one.
        try? await Task.sleep(for: .milliseconds(60))
        let ids: Set<UInt32> = [itemID, destination.targetID]
        guard await PlacementWait.stableFrames(of: ids) != nil,
              let source = CGEventSource(stateID: .hidSystemState),
              let hand = CGEvent(source: nil)?.location
        else { return false }

        let allowed: CGEventFilterMask = [
            .permitLocalMouseEvents,
            .permitLocalKeyboardEvents,
            .permitSystemDefinedEvents
        ]
        let states: [CGEventSuppressionState] = [
            .eventSuppressionStateRemoteMouseDrag,
            .eventSuppressionStateSuppressionInterval
        ]
        for state in states {
            source.setLocalEventsFilterDuringSuppressionState(allowed, state: state)
        }
        source.localEventsSuppressionInterval = 0

        CGDisplayHideCursor(CGMainDisplayID())
        defer {
            CGWarpMouseCursorPosition(hand)
            CGDisplayShowCursor(CGMainDisplayID())
        }

        // Route the press to the real item without putting the cursor on its parked,
        // off-screen frame. Once picked up, the item leaves the status-item layer; only its
        // destination can still be used as a stable anchor.
        post(.leftMouseDown, at: hand, windowID: itemID, source: source)
        try? await Task.sleep(for: .milliseconds(50))
        guard let finalFrames = await PlacementWait.stableFrames(
            of: idsThatMustRemainAfterMouseDown(itemID, destination: destination)
        ),
              let target = target(for: destination, in: finalFrames)
        else {
            post(.leftMouseUp, at: hand, windowID: itemID, source: source)
            return false
        }
        // A warp does not carry a drag. The dragged event moves the item into the chosen gap;
        // the release is routed to the item that was picked up, not the neighbouring window.
        post(.leftMouseDragged, at: target, windowID: itemID, source: source)
        try? await Task.sleep(for: .milliseconds(26))
        post(.leftMouseUp, at: target, windowID: itemID, source: source)
        try? await Task.sleep(for: .milliseconds(50))
        return true
    }

    static func idsThatMustRemainAfterMouseDown(
        _ itemID: UInt32, destination: StandaloneItemArrangement.Destination
    ) -> Set<UInt32> {
        [destination.targetID]
    }

    private static func target(
        for destination: StandaloneItemArrangement.Destination,
        in frames: [UInt32: CGRect]
    ) -> CGPoint? {
        let useLeftEdge: Bool
        switch destination {
        case .before: useLeftEdge = true
        case .after: useLeftEdge = false
        }
        guard let frame = frames[destination.targetID] else { return nil }
        return CGPoint(x: useLeftEdge ? frame.minX : frame.maxX, y: frame.midY)
    }

    private static func post(
        _ type: CGEventType,
        at point: CGPoint,
        windowID: UInt32,
        source: CGEventSource
    ) {
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else { return }
        event.flags = .maskCommand
        if let field = CGEventField(rawValue: 0x33) {
            event.setIntegerValueField(field, value: Int64(windowID))
        }
        event.post(tap: .cghidEventTap)
    }
}

private extension StandaloneItemArrangement.Destination {
    var targetID: UInt32 {
        switch self {
        case .before(let id), .after(let id): id
        }
    }
}
