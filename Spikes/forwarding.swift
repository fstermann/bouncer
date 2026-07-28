// Spike 12 — the click path, end to end.
//
// Two assumptions are still carrying the design, and both are inferences rather than
// measurements:
//
//   1. Clicks land once Accessibility is granted. Spike 4 only proved they are dropped
//      *without* it. "Denied without permission" does not imply "works with permission" —
//      status item windows are hosted by Control Center, and posting into another app's
//      remotely-hosted window is exactly where event routing tends to give up.
//
//   2. An item's menu appears somewhere useful. A status item anchors its menu to its own
//      window, which sits in the menu bar wherever the real item is. If the standalone bar
//      packs replicas left, a click on the third replica opens a menu under the seventh
//      item. That is the detail that makes a replica bar feel fake, and it decides whether
//      `MenuBarItemGeometry.layout` packs or mirrors.
//
// Everything is tested against this process's own status item, so no real item is
// triggered and nothing on the user's machine is toggled.

import AppKit

let logPath = "/tmp/bouncer-forwarding.log"

@MainActor
final class Spike: NSObject, NSApplicationDelegate {
    var victim: NSStatusItem?
    var clicks = 0
    var lastModifiers: NSEvent.ModifierFlags = []
    var lastWasRight = false
    var lines: [String] = []
    var preexisting: Set<Int> = []

    func note(_ s: String) {
        lines.append(s)
        try? lines.joined(separator: "\n").write(to: URL(fileURLWithPath: logPath),
                                                 atomically: true, encoding: .utf8)
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        preexisting = Set(statusWindows().map(\.number))

        // Seeded far right, or the item is created leftmost — which is inside Bouncer's
        // hidden section, and a click posted to an off-screen point proves nothing.
        UserDefaults.standard.set(0.5, forKey: "NSStatusItem Preferred Position bouncer.spike.forwarding")
        let item = NSStatusBar.system.statusItem(withLength: 47)
        item.autosaveName = "bouncer.spike.forwarding"
        item.button?.title = "◆"
        item.button?.target = self
        item.button?.action = #selector(hit)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        victim = item

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { Task { @MainActor in await self.run() } }
    }

    @objc func hit() {
        clicks += 1
        lastModifiers = NSApp.currentEvent?.modifierFlags ?? []
        lastWasRight = NSApp.currentEvent?.type == .rightMouseUp
    }

    struct Win { let number: Int; let layer: Int; let frame: CGRect; let owner: String }

    func statusWindows() -> [Win] {
        let raw = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        return raw.compactMap { d in
            guard d[kCGWindowLayer as String] as? Int == 25,
                  let n = d[kCGWindowNumber as String] as? Int,
                  let bd = d[kCGWindowBounds as String] as? [String: Any],
                  let r = CGRect(dictionaryRepresentation: bd as CFDictionary),
                  r.minY == 0, r.height <= 40 else { return nil }
            return Win(number: n, layer: 25, frame: r, owner: d[kCGWindowOwnerName as String] as? String ?? "?")
        }
    }

    /// Every window above the status layer — where a menu or popover would appear.
    func menuWindows() -> [Win] {
        let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return raw.compactMap { d in
            guard let layer = d[kCGWindowLayer as String] as? Int, layer > 25,
                  let n = d[kCGWindowNumber as String] as? Int,
                  let bd = d[kCGWindowBounds as String] as? [String: Any],
                  let r = CGRect(dictionaryRepresentation: bd as CFDictionary),
                  r.width > 40, r.height > 20 else { return nil }
            return Win(number: n, layer: layer, frame: r, owner: d[kCGWindowOwnerName as String] as? String ?? "?")
        }
    }

    func victimFrame() -> CGRect? {
        statusWindows().first { !preexisting.contains($0.number) && $0.frame.width < 300 }?.frame
    }

    func click(at point: CGPoint, method: String, right: Bool = false, flags: CGEventFlags = []) {
        let downType: CGEventType = right ? .rightMouseDown : .leftMouseDown
        let upType: CGEventType = right ? .rightMouseUp : .leftMouseUp
        let button: CGMouseButton = right ? .right : .left
        guard let down = CGEvent(mouseEventSource: nil, mouseType: downType,
                                 mouseCursorPosition: point, mouseButton: button),
              let up = CGEvent(mouseEventSource: nil, mouseType: upType,
                               mouseCursorPosition: point, mouseButton: button) else { return }
        down.flags = flags
        up.flags = flags
        switch method {
        case "sessionTap": down.post(tap: .cgSessionEventTap); up.post(tap: .cgSessionEventTap)
        case "hidTap": down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        case "postToPid":
            let pid = ProcessInfo.processInfo.processIdentifier
            down.postToPid(pid); up.postToPid(pid)
        default: break
        }
    }

    func attempt(_ method: String, right: Bool = false, flags: CGEventFlags = [], label: String) async {
        guard let frame = victimFrame() else { note("   \(label): no frame"); return }
        let before = clicks
        click(at: CGPoint(x: frame.midX, y: frame.midY), method: method, right: right, flags: flags)
        try? await Task.sleep(nanoseconds: 600_000_000)
        let landed = clicks > before
        var detail = landed ? "LANDED" : "no effect"
        if landed && right { detail += lastWasRight ? " (right preserved)" : " (arrived as LEFT)" }
        if landed && flags.contains(.maskAlternate) {
            detail += lastModifiers.contains(.option) ? " (option preserved)" : " (option LOST)"
        }
        note("   \(label.padding(toLength: 30, withPad: " ", startingAt: 0)) → \(detail)")
    }

    func run() async {
        let trusted = AXIsProcessTrusted()
        note("Accessibility trusted: \(trusted)")
        guard let frame = victimFrame() else { note("victim has no window"); NSApp.terminate(nil); return }
        note("victim item at x=\(Int(frame.minX)) w=\(Int(frame.width))")
        guard frame.minX >= 0 else {
            note("Victim landed off screen — reveal Bouncer's hidden section and re-run.")
            victim.map(NSStatusBar.system.removeStatusItem)
            NSApp.terminate(nil); return
        }
        note("")

        if trusted {
            // ---- 1. Does a forwarded click land, now that we are trusted? ----
            note("1. Click delivery with Accessibility granted")
            for m in ["sessionTap", "hidTap", "postToPid"] { await attempt(m, label: m) }

            // ---- 2. Modifiers and right click ----
            note("\n2. Modifier and right-click fidelity")
            await attempt("sessionTap", right: true, label: "right click")
            await attempt("sessionTap", flags: .maskAlternate, label: "option click")
        } else {
            note("1+2. Skipped — needs Accessibility. Menu anchoring below does not.")
        }

        // ---- 3. Where does the menu appear relative to the item? ----
        note("\n3. Menu anchoring")
        let menu = NSMenu()
        menu.addItem(withTitle: "Spike menu item one", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "Spike menu item two", action: nil, keyEquivalent: "")
        victim?.menu = menu

        let itemFrame = frame
        // popUp runs a modal loop, so the measurement has to happen from another thread
        // while the menu is up, and then dismiss it.
        let captured = UnsafeMutableTransferBox<[Win]>([])
        // The modal menu loop owns the main thread, so the snapshot must not hop back to
        // it — CGWindowListCopyWindowInfo is safe to call from anywhere, and hopping is
        // what deadlocked the first attempt. Escape dismisses the menu afterwards.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) {
            let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
                as? [[String: Any]] ?? []
            captured.value = raw.compactMap { d in
                guard let layer = d[kCGWindowLayer as String] as? Int, layer > 25,
                      let n = d[kCGWindowNumber as String] as? Int,
                      let bd = d[kCGWindowBounds as String] as? [String: Any],
                      let r = CGRect(dictionaryRepresentation: bd as CFDictionary),
                      r.width > 40, r.height > 20 else { return nil }
                return Win(number: n, layer: layer, frame: r,
                           owner: d[kCGWindowOwnerName as String] as? String ?? "?")
            }
            if let esc = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true) {
                esc.post(tap: .cgSessionEventTap)
            }
            if let escUp = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false) {
                escUp.post(tap: .cgSessionEventTap)
            }
        }
        let dismiss = Timer(timeInterval: 1.2, repeats: false) { _ in
            MainActor.assumeIsolated { self.victim?.menu?.cancelTracking() }
        }
        RunLoop.main.add(dismiss, forMode: .common)
        victim?.button?.performClick(nil)
        try? await Task.sleep(nanoseconds: 800_000_000)
        victim?.menu = nil

        let candidates = captured.value
            .filter { $0.frame.minY >= itemFrame.maxY - 8 && $0.frame.height > 30 }
            .sorted { abs($0.frame.minX - itemFrame.minX) < abs($1.frame.minX - itemFrame.minX) }

        if let menuWindow = candidates.first {
            let offset = menuWindow.frame.minX - itemFrame.minX
            note("   item at x=\(Int(itemFrame.minX)), menu at x=\(Int(menuWindow.frame.minX)) "
                 + "y=\(Int(menuWindow.frame.minY)) (\(menuWindow.owner), layer \(menuWindow.layer))")
            note(String(format: "   horizontal offset from the item: %+.0f pt", offset))
            note("   → " + (abs(offset) < 40
                            ? "the menu is anchored to the item's own x. Replicas must mirror real x "
                              + "positions, or menus will open away from the replica clicked."
                            : "the menu is not anchored to the item — layout is free to pack."))
        } else {
            note("   no menu window observed — \(captured.value.count) windows above the status layer")
            for w in captured.value.prefix(6) {
                note("     layer \(w.layer) \(w.owner) x=\(Int(w.frame.minX)) y=\(Int(w.frame.minY)) "
                     + "\(Int(w.frame.width))x\(Int(w.frame.height))")
            }
        }

        note("\ndone")
        victim.map(NSStatusBar.system.removeStatusItem)
        NSApp.terminate(nil)
    }
}

/// Small box so the background snapshot can be handed back without tripping strict
/// concurrency; the spike is single-threaded in practice.
final class UnsafeMutableTransferBox<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let d = Spike()
    app.delegate = d
    objc_setAssociatedObject(app, "d", d, .OBJC_ASSOCIATION_RETAIN)
    app.setActivationPolicy(.accessory)
    app.run()
}
