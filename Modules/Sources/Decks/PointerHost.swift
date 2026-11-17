import AppKit
import SwiftUI

/// Hosts the overview and reports where the pointer is in it.
///
/// SwiftUI's own hover tracking runs only while Bouncer is the active app, and the overview leaves the
/// user's app active until they pick a window. A tracking area that is always active does not care.
final class PointerHost<Content: View>: NSHostingView<Content> {
    /// The pointer's position in SwiftUI's coordinates, from the top left; `nil` once it leaves.
    var onPointer: (@MainActor (CGPoint?) -> Void)?
    /// A press, with whether Option is held; returns whether a drag starts there, which then takes the
    /// press from SwiftUI.
    var onPress: (@MainActor (CGPoint, Bool) -> Bool)?
    var onDrag: (@MainActor (CGPoint) -> Void)?
    var onRelease: (@MainActor (CGPoint) -> Void)?
    private var isDragging = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        report(event)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        report(event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onPointer?(nil)
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = onPress?(point(of: event), event.modifierFlags.contains(.option)) == true
        if !isDragging { super.mouseDown(with: event) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return super.mouseDragged(with: event) }
        onPointer?(point(of: event))
        onDrag?(point(of: event))
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return super.mouseUp(with: event) }
        isDragging = false
        onRelease?(point(of: event))
    }

    private func report(_ event: NSEvent) {
        onPointer?(point(of: event))
    }

    private func point(of event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return isFlipped ? point : CGPoint(x: point.x, y: bounds.height - point.y)
    }
}

/// What a part of the overview the pointer can be over is.
enum HoverTarget: Hashable {
    case deck(UUID)
    case window(CGWindowID)
    /// A window in the tray, which hovers only that card and keeps the tray open.
    case trayWindow(CGWindowID)
    case newDeck
    case tray
    case grid
}

/// Each target's frame in the overview, gathered from the views that draw them.
struct HoverFrames: PreferenceKey {
    static let defaultValue: [HoverTarget: CGRect] = [:]

    static func reduce(value: inout [HoverTarget: CGRect], nextValue: () -> [HoverTarget: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Reports this view's frame in the overview as `target`'s.
    func hoverTarget(_ target: HoverTarget) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(key: HoverFrames.self, value: [target: geometry.frame(in: .named(Hover.space))])
            }
        }
    }
}

enum Hover {
    static let space = "overview"

    /// The most specific target under `point`: a card before the tray or grid around it.
    static func target(at point: CGPoint?, in frames: [HoverTarget: CGRect]) -> HoverTarget? {
        guard let point else { return nil }
        let hits = frames.filter { $0.value.contains(point) }.map(\.key)
        return hits.first { if case .trayWindow = $0 { true } else { false } }
            ?? hits.first { $0 != .tray && $0 != .grid }
            ?? (hits.contains(.tray) ? .tray : nil)
            ?? (hits.contains(.grid) ? .grid : nil)
    }
}
