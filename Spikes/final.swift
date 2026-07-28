// Spike 2g + 3 — the two numbers the design hangs on, measured against a valid baseline.
//
// Established so far: a status item has pixels only while it is genuinely being drawn.
// Off the display it has none; in a fullscreen space it has none. So the standalone bar
// cannot refresh a hidden item — it can only show what was captured while that item was
// last visible.
//
// That leaves two questions:
//
//   1. OCCLUSION. Is "visible" about compositing or about being seen? A cover at 99% alpha
//      cannot be culled by the compositor, so if items stay capturable underneath one, we
//      can leave them on screen and hide them behind our own bar — always fresh, never
//      stale. This is the whole ballgame.
//
//   2. FLASH COST. If occlusion does suppress them, the fallback is reveal → capture →
//      re-hide on open. The cost of that is how long after collapsing the divider the items
//      become capturable, which is what the user would perceive as flicker.

import AppKit
import ScreenCaptureKit
import UniformTypeIdentifiers

let outDir: URL = {
    let b = Bundle.main.bundleURL
    return b.pathExtension == "app"
        ? b.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("out")
        : URL(fileURLWithPath: "Spikes/out")
}()

func write(_ image: CGImage, to name: String) {
    guard let d = CGImageDestinationCreateWithURL(
        outDir.appendingPathComponent(name) as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(d, image, nil)
    CGImageDestinationFinalize(d)
}

func inkPercent(_ image: CGImage?) -> Int {
    guard let image, let data = image.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else { return -1 }
    let w = image.width, h = image.height, bpr = image.bytesPerRow, bpp = image.bitsPerPixel / 8
    var lit = 0, total = 0
    for y in 0..<h {
        for x in 0..<w {
            let p = ptr + y * bpr + x * bpp
            if (bpp >= 4 ? Int(p[3]) : 255) > 24 { lit += 1 }
            total += 1
        }
    }
    return total > 0 ? lit * 100 / total : -1
}

func contactSheet(_ images: [CGImage]) -> CGImage? {
    guard !images.isEmpty else { return nil }
    let gap = 16
    let height = (images.map(\.height).max() ?? 0) + gap * 2
    let width = images.reduce(gap) { $0 + $1.width + gap }
    guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.setFillColor(CGColor(red: 0.30, green: 0.30, blue: 0.33, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    var x = gap
    for img in images {
        ctx.draw(img, in: CGRect(x: x, y: gap, width: img.width, height: img.height))
        x += img.width + gap
    }
    return ctx.makeImage()
}

struct Item { let windowID: CGWindowID; let frame: CGRect }

func statusItems(onScreenOnly: Bool) -> [Item] {
    let opts = CGWindowListOption(arrayLiteral: .optionAll, .excludeDesktopElements)
    guard let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return [] }
    return raw.compactMap { d -> Item? in
        guard d[kCGWindowLayer as String] as? Int == 25,
              let bd = d[kCGWindowBounds as String] as? [String: Any],
              let r = CGRect(dictionaryRepresentation: bd as CFDictionary),
              r.minY == 0, r.height <= 40, r.width < 300 else { return nil }
        if onScreenOnly && r.minX < 0 { return nil }
        if !onScreenOnly && r.minX >= 0 { return nil }
        return Item(windowID: CGWindowID(d[kCGWindowNumber as String] as? Int ?? 0), frame: r)
    }.sorted { $0.frame.minX < $1.frame.minX }
}

@MainActor
final class Spike: NSObject, NSApplicationDelegate {
    var cover: NSWindow?
    /// Our own divider, so the flash measurement does not depend on driving Bouncer.
    var divider: NSStatusItem?

    func applicationDidFinishLaunching(_ note: Notification) {
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        freopen(outDir.appendingPathComponent("final.log").path, "w", stdout)
        setvbuf(stdout, nil, _IOLBF, 0)
        Task { await self.run() }
    }

    func makeCover(_ rect: CGRect, opaque: Bool) -> NSWindow {
        let screen = NSScreen.main!
        let frame = CGRect(x: rect.minX, y: screen.frame.height - rect.maxY,
                           width: rect.width, height: rect.height)
        let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        w.isOpaque = opaque
        w.backgroundColor = opaque ? .black : NSColor.black.withAlphaComponent(0.99)
        w.orderFrontRegardless()
        return w
    }

    func capture(_ win: SCWindow) async -> CGImage? {
        let cfg = SCStreamConfiguration()
        cfg.width = Int(win.frame.width * 2)
        cfg.height = Int(win.frame.height * 2)
        cfg.showsCursor = false
        cfg.captureResolution = .best
        return try? await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: win), configuration: cfg)
    }

    func shareable() async -> [CGWindowID: SCWindow] {
        guard let c = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: c.windows.map { ($0.windowID, $0) })
    }

    func run() async {
        guard CGPreflightScreenCaptureAccess() else {
            print("not granted"); CGRequestScreenCaptureAccess(); NSApp.terminate(nil); return
        }

        let items = statusItems(onScreenOnly: true)
        guard !items.isEmpty else { print("no on-screen items"); NSApp.terminate(nil); return }
        let strip = items.dropFirst().reduce(items[0].frame) { $0.union($1.frame) }
        var byID = await shareable()
        print("\(items.count) on-screen items, strip x=\(Int(strip.minX)) w=\(Int(strip.width))\n")

        // ---- Fidelity + baseline ----
        print("1. Uncovered")
        var sheet: [CGImage] = []
        var baseline: [CGWindowID: Int] = [:]
        for item in items {
            guard let win = byID[item.windowID] else { continue }
            let img = await capture(win)
            baseline[item.windowID] = inkPercent(img)
            print("   x=\(Int(item.frame.minX)) w=\(Int(item.frame.width)) ink=\(inkPercent(img))%")
            if let img { sheet.append(img) }
        }
        if let s = contactSheet(sheet) { write(s, to: "I-uncovered.png") }
        let baselineTotal = baseline.values.reduce(0, +)

        // ---- 2. Occlusion: opaque control, then 99% alpha ----
        for (label, opaque) in [("opaque cover (control)", true), ("99% alpha cover", false)] {
            cover = makeCover(strip, opaque: opaque)
            try? await Task.sleep(nanoseconds: 700_000_000)
            byID = await shareable()
            var covered: [CGImage] = []
            var total = 0
            for item in items {
                guard let win = byID[item.windowID] else { continue }
                let img = await capture(win)
                total += max(inkPercent(img), 0)
                if let img { covered.append(img) }
            }
            print("\n2. \(label): total ink \(total)% vs baseline \(baselineTotal)%")
            if let s = contactSheet(covered) {
                write(s, to: "I-\(opaque ? "opaque" : "alpha99").png")
            }
            print("   → " + (total >= baselineTotal - 5 ? "SURVIVES" : "suppressed"))
            cover?.orderOut(nil); cover = nil
            try? await Task.sleep(nanoseconds: 400_000_000)
        }

        // ---- 3. Flash cost: how long after revealing until items are capturable? ----
        print("\n3. Reveal → capturable latency (our own divider, 8 cycles)")
        let d = NSStatusBar.system.statusItem(withLength: 10_000)
        d.autosaveName = "BouncerSpikeDivider"
        d.button?.window?.ignoresMouseEvents = true
        divider = d
        try? await Task.sleep(nanoseconds: 1_200_000_000)

        let hidden = statusItems(onScreenOnly: false)
        print("   divider pushed \(hidden.count) items off screen")
        guard let victim = hidden.last else {
            print("   no item got hidden — cannot measure flash")
            NSStatusBar.system.removeStatusItem(d)
            print("\ndone"); NSApp.terminate(nil); return
        }

        var latencies: [Double] = []
        for cycle in 0..<8 {
            d.length = 1  // reveal
            let t0 = DispatchTime.now().uptimeNanoseconds
            var elapsed = 0.0
            // The window moves back on screen and gets a new frame; re-resolve each poll.
            while elapsed < 800 {
                let onNow = statusItems(onScreenOnly: true)
                if let match = onNow.first(where: { $0.windowID == victim.windowID }) {
                    let fresh = await shareable()
                    if let win = fresh[match.windowID], let img = await capture(win), inkPercent(img) > 0 {
                        elapsed = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
                        break
                    }
                }
                elapsed = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
            }
            latencies.append(elapsed)
            if cycle == 0 { print("   cycle 0: \(Int(elapsed)) ms") }
            d.length = 10_000  // hide again
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        latencies.sort()
        print(String(format: "   median %.0f ms, min %.0f, max %.0f  (one frame = 16.7 ms)",
                     latencies[latencies.count / 2], latencies.first ?? 0, latencies.last ?? 0))

        NSStatusBar.system.removeStatusItem(d)
        print("\ndone")
        NSApp.terminate(nil)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = Spike()
    app.delegate = delegate
    objc_setAssociatedObject(app, "d", delegate, .OBJC_ASSOCIATION_RETAIN)
    app.setActivationPolicy(.accessory)
    app.run()
}
