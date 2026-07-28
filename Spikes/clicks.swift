// Spike 4 — can a click reach an item the user cannot see?
//
// The capture spikes settled the picture: items must stay on the display and stay drawn,
// but they may be covered. So the standalone bar leaves every item exactly where it is,
// covers that stretch of menu bar with an opaque window, and draws replicas below. A click
// on a replica has to end up at the real item, which is sitting under the cover at a known
// on-screen point.
//
// Two things to find out, and the second one decides whether this feature is allowed to
// exist under Bouncer's no-new-permissions rule:
//
//   1. Does a synthesised click land on the item when our cover is above it?
//   2. Does posting that click require Accessibility? CGEvent.post to a session tap is
//      normally gated on it. If it is, that is a second permission prompt, and the design
//      has to change (or the feature stays off by default).
//
// Self-contained: the spike creates its own status item and clicks that, so nothing on the
// user's real menu bar is triggered.

import AppKit

@MainActor
final class Spike: NSObject, NSApplicationDelegate {
    var victim: NSStatusItem?
    var cover: NSWindow?
    var clicks = 0
    /// Window numbers present before our item existed, so it can be identified by
    /// difference — its width is not what we asked for (the system adds padding) and its
    /// local NSWindow number does not appear in the global list.
    var preexisting: Set<Int> = []
    var log: [String] = []

    func note(_ s: String) {
        log.append(s)
        try? log.joined(separator: "\n").write(
            to: URL(fileURLWithPath: "/tmp/bouncer-clicks.log"), atomically: true, encoding: .utf8)
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        note("Accessibility trusted: \(AXIsProcessTrusted())")
        preexisting = Set(statusWindowNumbers())

        // Seeded to the far right so it lands on the visible side of Bouncer's divider —
        // otherwise a new item is created leftmost, which is inside the hidden section.
        UserDefaults.standard.set(0.5, forKey: "NSStatusItem Preferred Position bouncer.spike.victim")
        let item = NSStatusBar.system.statusItem(withLength: 47)
        item.autosaveName = "bouncer.spike.victim"
        item.button?.title = "▓"
        item.button?.target = self
        item.button?.action = #selector(hit)
        victim = item

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { Task { @MainActor in await self.run() } }
    }

    @objc func hit() { clicks += 1 }

    /// Status item windows are hosted out of process — every one of them reports Control
    /// Center as its owner and carries a window number that does not match the local
    /// NSWindow. So the item is found by the one thing we control about it: an unusual
    /// width no real item is likely to have.
    func statusWindowNumbers() -> [Int] {
        let raw = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        return raw.compactMap { d in
            guard d[kCGWindowLayer as String] as? Int == 25,
                  let bd = d[kCGWindowBounds as String] as? [String: Any],
                  let r = CGRect(dictionaryRepresentation: bd as CFDictionary),
                  r.minY == 0, r.height <= 40 else { return nil }
            return d[kCGWindowNumber as String] as? Int
        }
    }

    func victimFrame() -> CGRect? {
        let raw = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        for d in raw {
            guard d[kCGWindowLayer as String] as? Int == 25,
                  let number = d[kCGWindowNumber as String] as? Int, !preexisting.contains(number),
                  let bd = d[kCGWindowBounds as String] as? [String: Any],
                  let r = CGRect(dictionaryRepresentation: bd as CFDictionary),
                  r.minY == 0, r.height <= 40, r.width < 300 else { continue }
            return r
        }
        return nil
    }

    func click(at point: CGPoint, via method: String) {
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                 mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                               mouseCursorPosition: point, mouseButton: .left)
        else { note("   could not build events"); return }

        switch method {
        case "sessionTap":
            down.post(tap: .cgSessionEventTap)
            up.post(tap: .cgSessionEventTap)
        case "hidTap":
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        case "postToPid":
            // Every status item window reports Control Center as its owner, so this is the
            // process that would have to route the click for a real third-party item.
            let pid = ProcessInfo.processInfo.processIdentifier
            down.postToPid(pid)
            up.postToPid(pid)
        default: break
        }
    }

    func attempt(_ method: String, covered: Bool) async {
        guard let frame = victimFrame() else { note("\(method): no frame"); return }
        let point = CGPoint(x: frame.midX, y: frame.midY)
        let before = clicks
        click(at: point, via: method)
        try? await Task.sleep(nanoseconds: 500_000_000)
        let landed = clicks > before
        note("   \(method.padding(toLength: 12, withPad: " ", startingAt: 0)) "
             + "covered=\(covered ? "yes" : "no ") → \(landed ? "LANDED" : "no effect")")
    }

    func showCover(_ frame: CGRect, passThrough: Bool) {
        let screen = NSScreen.main!
        let rect = CGRect(x: frame.minX, y: screen.frame.height - frame.maxY,
                          width: frame.width, height: frame.height)
        let w = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        w.backgroundColor = .black
        w.isOpaque = true
        w.ignoresMouseEvents = passThrough
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        w.orderFrontRegardless()
        cover = w
    }

    func run() async {
        guard let frame = victimFrame() else {
            let raw = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
            let widths = raw.compactMap { d -> String? in
                guard d[kCGWindowLayer as String] as? Int == 25,
                      let bd = d[kCGWindowBounds as String] as? [String: Any],
                      let r = CGRect(dictionaryRepresentation: bd as CFDictionary) else { return nil }
                return "x=\(Int(r.minX))/w=\(Int(r.width))"
            }
            note("no width-47 item. layer-25 windows: \(widths.joined(separator: " "))")
            note("button exists: \(victim?.button != nil), isVisible: \(victim?.isVisible ?? false)")
            NSApp.terminate(nil); return
        }
        note("victim window at x=\(Int(frame.minX)) w=\(Int(frame.width))\n")

        note("uncovered:")
        for m in ["sessionTap", "hidTap", "postToPid"] { await attempt(m, covered: false) }

        note("\ncovered, cover swallows mouse events (ignoresMouseEvents = false):")
        showCover(frame, passThrough: false)
        try? await Task.sleep(nanoseconds: 400_000_000)
        for m in ["sessionTap", "hidTap", "postToPid"] { await attempt(m, covered: true) }
        cover?.orderOut(nil)

        note("\ncovered, cover passes mouse events through (ignoresMouseEvents = true):")
        showCover(frame, passThrough: true)
        try? await Task.sleep(nanoseconds: 400_000_000)
        for m in ["sessionTap", "hidTap", "postToPid"] { await attempt(m, covered: true) }
        cover?.orderOut(nil)

        note("\ntotal clicks received: \(clicks)")
        note("done")
        victim.map(NSStatusBar.system.removeStatusItem)
        NSApp.terminate(nil)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let d = Spike()
    app.delegate = d
    objc_setAssociatedObject(app, "d", d, .OBJC_ASSOCIATION_RETAIN)
    app.setActivationPolicy(.accessory)
    app.run()
}
