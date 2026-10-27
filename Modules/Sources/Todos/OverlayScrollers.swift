import AppKit
import SwiftUI

/// Thin scrollers that show only while scrolling, over the list it lies in, whatever the system
/// setting: the always-on ones take a wide strip of the panel and look out of place on it.
struct OverlayScrollers: NSViewRepresentable {
    func makeNSView(context: Context) -> OverlayScrollersView { OverlayScrollersView() }
    func updateNSView(_ view: OverlayScrollersView, context: Context) {}
}

final class OverlayScrollersView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        enclosingScrollView?.scrollerStyle = .overlay
        enclosingScrollView?.scrollerKnobStyle = .light
    }
}
