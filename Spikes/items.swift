// Spike 2e — dump every status item, covered and uncovered, and look at the pixels.
//
// Three runs in a row drew conclusions from a summary statistic that turned out to be
// measuring the wrong thing, so this one commits to visual evidence: capture each item
// with the filter proven to work (per-window), write a PNG per item, and lay them out in a
// contact sheet. Then the same again with a 99%-alpha cover over the strip.
//
// Settles two questions at once:
//   - fidelity: what does a replicated item actually look like?
//   - occlusion: does a cover the compositor cannot cull keep them capturable?

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

/// Lays the captures out side by side on a mid grey, so alpha and glyph shape are both
/// obvious at a glance.
func contactSheet(_ images: [CGImage], scale: Int = 2) -> CGImage? {
    guard !images.isEmpty else { return nil }
    let gap = 8 * scale
    let height = (images.map(\.height).max() ?? 0) + gap * 2
    let width = images.reduce(gap) { $0 + $1.width + gap }
    guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.setFillColor(CGColor(red: 0.35, green: 0.35, blue: 0.38, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    var x = gap
    for img in images {
        ctx.draw(img, in: CGRect(x: x, y: gap, width: img.width, height: img.height))
        x += img.width + gap
    }
    return ctx.makeImage()
}

struct Item { let windowID: CGWindowID; let frame: CGRect }

func statusItems() -> [Item] {
    let opts = CGWindowListOption(arrayLiteral: .optionAll, .excludeDesktopElements)
    guard let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return [] }
    return raw.compactMap { d -> Item? in
        guard d[kCGWindowLayer as String] as? Int == 25,
              let bd = d[kCGWindowBounds as String] as? [String: Any],
              let r = CGRect(dictionaryRepresentation: bd as CFDictionary),
              r.minY == 0, r.height <= 40, r.width < 300 else { return nil }
        return Item(windowID: CGWindowID(d[kCGWindowNumber as String] as? Int ?? 0), frame: r)
    }.sorted { $0.frame.minX < $1.frame.minX }
}

@MainActor
final class Spike: NSObject, NSApplicationDelegate {
    var cover: NSWindow?

    func applicationDidFinishLaunching(_ note: Notification) {
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        freopen(outDir.appendingPathComponent("items.log").path, "w", stdout)
        setvbuf(stdout, nil, _IOLBF, 0)
        Task { await self.run() }
    }

    func makeCover(covering rect: CGRect) -> NSWindow {
        let screen = NSScreen.main!
        let frame = CGRect(x: rect.minX, y: screen.frame.height - rect.maxY,
                           width: rect.width, height: rect.height)
        let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        w.isOpaque = false
        w.backgroundColor = NSColor.black.withAlphaComponent(0.99)
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

    func run() async {
        guard CGPreflightScreenCaptureAccess() else {
            print("not granted"); CGRequestScreenCaptureAccess(); NSApp.terminate(nil); return
        }
        let items = statusItems().filter { $0.frame.minX >= 0 }
        guard !items.isEmpty else { print("no on-screen items"); NSApp.terminate(nil); return }
        let strip = items.dropFirst().reduce(items[0].frame) { $0.union($1.frame) }
        print("\(items.count) on-screen items, strip x=\(Int(strip.minX)) w=\(Int(strip.width))\n")

        func resolve() async -> [(Item, SCWindow)] {
            guard let c = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            else { return [] }
            let byID = Dictionary(uniqueKeysWithValues: c.windows.map { ($0.windowID, $0) })
            return items.compactMap { item in byID[item.windowID].map { (item, $0) } }
        }

        // ---- Uncovered ----
        print("Uncovered:")
        var uncovered: [CGImage] = []
        for (item, win) in await resolve() {
            let img = await capture(win)
            print("   x=\(Int(item.frame.minX)) w=\(Int(item.frame.width)) → "
                  + (img.map { "\($0.width)x\($0.height) ink=\(inkPercent($0))%" } ?? "nil"))
            if let img { uncovered.append(img); write(img, to: "G-item-\(Int(item.frame.minX)).png") }
        }
        if let sheet = contactSheet(uncovered) { write(sheet, to: "G-uncovered-sheet.png") }

        // ---- Covered by a 99%-alpha window the compositor cannot cull ----
        cover = makeCover(covering: strip)
        try? await Task.sleep(nanoseconds: 700_000_000)
        print("\nCovered (99% alpha over the whole strip):")
        var covered: [CGImage] = []
        for (item, win) in await resolve() {
            let img = await capture(win)
            print("   x=\(Int(item.frame.minX)) w=\(Int(item.frame.width)) → "
                  + (img.map { "\($0.width)x\($0.height) ink=\(inkPercent($0))%" } ?? "nil"))
            if let img { covered.append(img) }
        }
        if let sheet = contactSheet(covered) { write(sheet, to: "G-covered-sheet.png") }
        cover?.orderOut(nil)
        cover = nil

        // ---- Cost of one full refresh, all items, sequential vs concurrent ----
        let resolved = await resolve()
        let t0 = DispatchTime.now().uptimeNanoseconds
        for (_, win) in resolved { _ = await capture(win) }
        let sequential = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000

        let t1 = DispatchTime.now().uptimeNanoseconds
        await withTaskGroup(of: Void.self) { group in
            for (_, win) in resolved {
                group.addTask { @MainActor in _ = await self.capture(win) }
            }
        }
        let concurrent = Double(DispatchTime.now().uptimeNanoseconds - t1) / 1_000_000

        print(String(format: "\nFull refresh of %d items: sequential %.1f ms, concurrent %.1f ms",
                     resolved.count, sequential, concurrent))
        print("\ndone")
        NSApp.terminate(nil)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = Spike()
    app.delegate = delegate
    objc_setAssociatedObject(app, "spike", delegate, .OBJC_ASSOCIATION_RETAIN)
    app.setActivationPolicy(.accessory)
    app.run()
}
