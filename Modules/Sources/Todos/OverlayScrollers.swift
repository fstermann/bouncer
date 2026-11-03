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

/// Puts the list it lies in back where it was scrolled to, and reports each scroll: the panel builds
/// its page afresh on every open, scroll view and all. It watches the scrolling only while in a window.
struct ScrollMemory: NSViewRepresentable {
    /// From the top of the list.
    let offset: CGFloat
    let onScroll: @MainActor (CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollMemoryView { ScrollMemoryView(offset: offset, onScroll: onScroll) }
    func updateNSView(_ view: ScrollMemoryView, context: Context) {}
}

final class ScrollMemoryView: NSView {
    private let offset: CGFloat
    private let onScroll: @MainActor (CGFloat) -> Void
    private weak var clip: NSClipView?

    init(offset: CGFloat, onScroll: @escaping @MainActor (CGFloat) -> Void) {
        self.offset = offset
        self.onScroll = onScroll
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let clip {
            NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: clip)
        }
        guard window != nil, let scrollView = enclosingScrollView else { return }
        // A turn later, once the rows are laid out and the list is as tall as it will be.
        DispatchQueue.main.async { [weak self] in
            guard let self, let document = scrollView.documentView else { return }
            let clip = scrollView.contentView
            let top = min(offset, room(in: clip, document))
            clip.scroll(to: NSPoint(x: 0, y: document.isFlipped ? top : room(in: clip, document) - top))
            scrollView.reflectScrolledClipView(clip)
            self.clip = clip
            clip.postsBoundsChangedNotifications = true
            // A selector observer, which goes with the view when the panel lets go of it.
            NotificationCenter.default.addObserver(
                self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: clip
            )
        }
    }

    @objc private func scrolled() {
        guard let clip, let document = clip.documentView else { return }
        onScroll(document.isFlipped ? clip.bounds.minY : room(in: clip, document) - clip.bounds.minY)
    }

    private func room(in clip: NSClipView, _ document: NSView) -> CGFloat {
        max(document.bounds.height - clip.bounds.height, 0)
    }
}
