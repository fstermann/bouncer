import AppKit
import SwiftUI
import Testing

@testable import Decks

@MainActor
@Suite struct OverviewScrollTests {
    @Test func scrollingBringsTheLastRowIntoReach() async throws {
        let windows = (1...50).map { index in
            WindowInfo(id: CGWindowID(index), pid: 1, bundleID: "app", appName: "App",
                       title: "Window \(index)", frame: .zero)
        }
        let overview = Overview(windows: windows, decks: [], wallpaper: nil, canRaise: true, canSeeTitles: true)
        let viewport = CGRect(x: 0, y: 0, width: 1280, height: 800)
        let panel = OverlayPanel(frame: viewport)
        let host = PointerHost(rootView: OverviewView(overview: overview))
        host.sizingOptions = []
        panel.contentView = host
        panel.setFrame(viewport, display: false)
        host.layoutSubtreeIfNeeded()
        let scroll = try #require(scrollView(inside: host))
        let document = try #require(scroll.documentView)
        let last = HoverTarget.window(50)
        let before = try #require(overview.hoverFrames[last])
        #expect(before.minY > viewport.maxY)

        let bottom = document.isFlipped ? document.bounds.height - scroll.contentView.bounds.height : 0
        scroll.contentView.scroll(to: CGPoint(x: 0, y: bottom))
        scroll.reflectScrolledClipView(scroll.contentView)
        for _ in 0..<100 {
            host.layoutSubtreeIfNeeded()
            if let frame = overview.hoverFrames[last], viewport.contains(frame) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let after = try #require(overview.hoverFrames[last])
        #expect(viewport.contains(after))
        let point = CGPoint(x: after.midX, y: after.midY)
        var picked: [WindowInfo] = []
        overview.onPick = { picked = $0 }
        #expect(overview.press(at: point))
        overview.released(at: point)
        #expect(picked.map(\.id) == [50])
    }

    private func scrollView(inside view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for subview in view.subviews {
            if let scroll = scrollView(inside: subview) { return scroll }
        }
        return nil
    }
}
