// Spike 7 — prove it on the items that actually need replicating.
//
// Every capture measurement so far used the items at x >= 1191: the ones that were never
// hidden. The items the standalone bar exists to show are the ones Bouncer has pushed to
// x = -4079…-3856, and those are precisely the ones with no pixels. The occlusion result
// ought to generalise — per-window capture does not care what is on top of a window, and
// nothing about it was specific to those items — but that is an argument, not a
// measurement.
//
// So this runs the production path on the real population:
//
//   1. Note which items are currently off screen — the hidden section.
//   2. Wait for the user to reveal it (click Bouncer's boundary).
//   3. The moment those windows land on screen, cover that stretch and capture each one.
//   4. Report whether the previously-hidden items captured, and how wide the cover has to
//      be to hide them.
//
// If they come back clean, "cover, don't displace" is proven on the items it is for.

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

struct Item { let number: Int; let frame: CGRect }

func items() -> [Item] {
    let raw = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] ?? []
    return raw.compactMap { d -> Item? in
        guard d[kCGWindowLayer as String] as? Int == 25,
              let n = d[kCGWindowNumber as String] as? Int,
              let bd = d[kCGWindowBounds as String] as? [String: Any],
              let r = CGRect(dictionaryRepresentation: bd as CFDictionary),
              r.minY == 0, r.height <= 40, r.width < 300 else { return nil }
        return Item(number: n, frame: r)
    }.sorted { $0.frame.minX < $1.frame.minX }
}

@MainActor
final class Spike: NSObject, NSApplicationDelegate {
    var cover: NSWindow?

    func applicationDidFinishLaunching(_ n: Notification) {
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        freopen(outDir.appendingPathComponent("hidden.log").path, "w", stdout)
        setvbuf(stdout, nil, _IOLBF, 0)
        Task { await self.run() }
    }

    func showCover(_ rect: CGRect) {
        let screen = NSScreen.main!
        let frame = CGRect(x: rect.minX, y: screen.frame.height - rect.maxY,
                           width: rect.width, height: rect.height)
        let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        w.ignoresMouseEvents = true
        w.isOpaque = true
        w.backgroundColor = .black
        w.orderFrontRegardless()
        cover = w
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

    func run() async {
        guard CGPreflightScreenCaptureAccess() else {
            print("not granted"); CGRequestScreenCaptureAccess(); NSApp.terminate(nil); return
        }

        let hiddenNow = items().filter { $0.frame.minX < 0 }
        guard !hiddenNow.isEmpty else {
            print("Nothing is hidden right now — collapse Bouncer first, then re-run.")
            NSApp.terminate(nil); return
        }
        let targets = Set(hiddenNow.map(\.number))
        print("Hidden section: \(hiddenNow.count) items at x="
              + hiddenNow.map { String(Int($0.frame.minX)) }.joined(separator: ", "))
        print("Total width they occupy: \(Int(hiddenNow.reduce(0) { $0 + $1.frame.width })) pt")
        print("\nWaiting up to 90 s for you to reveal the hidden section…")

        // Wait for those exact windows to arrive on screen.
        var revealed: [Item] = []
        let deadline = DispatchTime.now().uptimeNanoseconds + 90_000_000_000
        while DispatchTime.now().uptimeNanoseconds < deadline {
            let onScreen = items().filter { targets.contains($0.number) && $0.frame.minX >= 0 }
            if onScreen.count >= max(1, hiddenNow.count - 1) { revealed = onScreen; break }
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        guard !revealed.isEmpty else {
            print("Never revealed — nothing measured."); NSApp.terminate(nil); return
        }

        let strip = revealed.dropFirst().reduce(revealed[0].frame) { $0.union($1.frame) }
        print("Revealed \(revealed.count) of them: strip x=\(Int(strip.minX)) w=\(Int(strip.width))")

        // Cover immediately, then capture through the cover — the production path.
        showCover(strip)
        try? await Task.sleep(nanoseconds: 500_000_000)

        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        else { print("no shareable content"); NSApp.terminate(nil); return }
        let byID = Dictionary(uniqueKeysWithValues: content.windows.map { ($0.windowID, $0) })

        print("\nCapturing the previously-hidden items, through an opaque cover:")
        var sheet: [CGImage] = []
        var captured = 0
        for item in revealed {
            guard let win = byID[CGWindowID(item.number)] else {
                print("   x=\(Int(item.frame.minX)) not shareable"); continue
            }
            let img = await capture(win)
            let pct = inkPercent(img)
            if pct > 0 { captured += 1 }
            print("   x=\(Int(item.frame.minX)) w=\(Int(item.frame.width)) → ink=\(pct)%")
            if let img { sheet.append(img) }
        }
        if let s = contactSheet(sheet) { write(s, to: "J-hidden-items.png") }

        cover?.orderOut(nil)
        cover = nil

        print("\n\(captured)/\(revealed.count) previously-hidden items captured through the cover.")
        print(captured == revealed.count
              ? "Cover-don't-displace holds for the items it is actually for."
              : "Some items did not capture — investigate before building on this.")
        print("\ndone")
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
