// Spike 2b — the pivot test.
//
// Spike 2 established that a status item parked off the display has no pixels: the window
// server does not composite it. So hiding by displacement and replicating by capture are
// mutually exclusive, and the standalone bar needs items to stay *on* the display.
//
// The alternative is to hide them by covering: leave the items where they are and put an
// opaque window over that stretch of menu bar. This spike asks whether that survives
// capture — a window-based capture is supposed to ignore occlusion, but "supposed to" is
// what the last spike cost us.
//
// Measures:
//   1. Does per-window capture of an item still return pixels while our overlay covers it?
//   2. Does a display-scoped capture filtered to just the item windows exclude the overlay?
//   3. How fast is one strip capture of the whole section, on screen? (the number that
//      decides whether the bar can open within a frame)
//
// Build into the already-approved bundle so the TCC grant is reused.

import AppKit
import ScreenCaptureKit
import UniformTypeIdentifiers

let outDir: URL = {
    let bundle = Bundle.main.bundleURL
    return bundle.pathExtension == "app"
        ? bundle.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("out")
        : URL(fileURLWithPath: "Spikes/out")
}()

func write(_ image: CGImage, to name: String) {
    guard let dest = CGImageDestinationCreateWithURL(
        outDir.appendingPathComponent(name) as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

func describe(_ image: CGImage?) -> String {
    guard let image, let data = image.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else {
        return image.map { "\($0.width)x\($0.height) (no data)" } ?? "nil"
    }
    let w = image.width, h = image.height, bpr = image.bytesPerRow, bpp = image.bitsPerPixel / 8
    var opaque = 0, total = 0
    for y in stride(from: 0, to: h, by: max(1, h / 16)) {
        for x in stride(from: 0, to: w, by: max(1, w / 16)) {
            let p = ptr + y * bpr + x * bpp
            if (bpp >= 4 ? Int(p[3]) : 255) > 16 { opaque += 1 }
            total += 1
        }
    }
    return "\(w)x\(h) opaque=\(total > 0 ? opaque * 100 / total : 0)%"
}

struct Item {
    let windowID: CGWindowID
    let frame: CGRect
    var isDivider: Bool { frame.width > 300 }
}

func statusItems() -> [Item] {
    let opts = CGWindowListOption(arrayLiteral: .optionAll, .excludeDesktopElements)
    guard let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return [] }
    return raw.compactMap { d -> Item? in
        guard d[kCGWindowLayer as String] as? Int == 25,
              let bd = d[kCGWindowBounds as String] as? [String: Any],
              let r = CGRect(dictionaryRepresentation: bd as CFDictionary),
              r.minY == 0, r.height <= 40 else { return nil }
        return Item(windowID: CGWindowID(d[kCGWindowNumber as String] as? Int ?? 0), frame: r)
    }.sorted { $0.frame.minX < $1.frame.minX }
}

@MainActor
final class Spike: NSObject, NSApplicationDelegate {
    var overlay: NSWindow?

    func applicationDidFinishLaunching(_ note: Notification) {
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        freopen(outDir.appendingPathComponent("occlusion.log").path, "w", stdout)
        setvbuf(stdout, nil, _IOLBF, 0)
        Task { await self.run() }
    }

    /// Status items sit at CG level 25. The overlay has to beat that, but stay under the
    /// pop-up menu level (101) so an item's own menu still draws above it when clicked.
    func makeOverlay(covering rect: CGRect) -> NSWindow {
        let screen = NSScreen.main!
        // CG coordinates are top-left origin; AppKit windows are bottom-left.
        let appKitRect = CGRect(x: rect.minX, y: screen.frame.height - rect.maxY,
                                width: rect.width, height: rect.height)
        let window = NSWindow(contentRect: appKitRect, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        window.backgroundColor = .systemPink
        window.isOpaque = true
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.orderFrontRegardless()
        return window
    }

    func run() async {
        guard CGPreflightScreenCaptureAccess() else {
            print("Screen Recording not granted — rebuild changed the code signature?")
            CGRequestScreenCaptureAccess()
            NSApp.terminate(nil)
            return
        }

        let items = statusItems().filter { !$0.isDivider }
        let onScreen = items.filter { $0.frame.minX >= 0 }
        guard let probe = onScreen.first, !onScreen.isEmpty else {
            print("no on-screen status items"); NSApp.terminate(nil); return
        }
        let strip = onScreen.dropFirst().reduce(onScreen[0].frame) { $0.union($1.frame) }
        print("On-screen items: \(onScreen.count), strip x=\(Int(strip.minX)) w=\(Int(strip.width))")
        print("Probe: win \(probe.windowID) at x=\(Int(probe.frame.minX)) w=\(Int(probe.frame.width))\n")

        let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let content, let display = content.displays.first else {
            print("no shareable content"); NSApp.terminate(nil); return
        }
        let byID = Dictionary(uniqueKeysWithValues: content.windows.map { ($0.windowID, $0) })
        guard let scProbe = byID[probe.windowID] else {
            print("probe not in shareable content"); NSApp.terminate(nil); return
        }

        func captureWindow(_ win: SCWindow, _ name: String) async -> CGImage? {
            let cfg = SCStreamConfiguration()
            cfg.width = Int(win.frame.width * 2)
            cfg.height = Int(win.frame.height * 2)
            cfg.showsCursor = false
            let filter = SCContentFilter(desktopIndependentWindow: win)
            let img = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
            if let img { write(img, to: name) }
            return img
        }

        print("1. Per-window capture, nothing covering it")
        print("   \(describe(await captureWindow(scProbe, "D-uncovered.png")))\n")

        // ---- Cover the whole strip and try again ----
        overlay = makeOverlay(covering: strip)
        try? await Task.sleep(nanoseconds: 400_000_000)
        print("2. Per-window capture, overlay covering the strip")
        print("   \(describe(await captureWindow(scProbe, "D-covered.png")))\n")

        // ---- Display-scoped capture of just the items: does it leak the overlay? ----
        print("3. Strip capture (display filter including only the item windows)")
        let cfg = SCStreamConfiguration()
        cfg.sourceRect = strip
        cfg.width = Int(strip.width * 2)
        cfg.height = Int(strip.height * 2)
        cfg.showsCursor = false
        cfg.ignoreGlobalClipDisplay = true
        let stripFilter = SCContentFilter(display: display, including: onScreen.compactMap { byID[$0.windowID] })
        if let img = try? await SCScreenshotManager.captureImage(contentFilter: stripFilter, configuration: cfg) {
            print("   \(describe(img))")
            write(img, to: "D-strip.png")
        } else {
            print("   FAILED")
        }

        var samples: [Double] = []
        for _ in 0..<30 {
            let t0 = DispatchTime.now().uptimeNanoseconds
            _ = try? await SCScreenshotManager.captureImage(contentFilter: stripFilter, configuration: cfg)
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)
        }
        samples.sort()
        print(String(format: "   30 strip captures: median %.2f ms (min %.2f, max %.2f)",
                     samples[15], samples.first ?? 0, samples.last ?? 0))

        // ---- What the user actually sees while the overlay is up ----
        let shotCfg = SCStreamConfiguration()
        shotCfg.sourceRect = CGRect(x: 0, y: 0, width: display.width, height: 40)
        shotCfg.width = display.width * 2
        shotCfg.height = 80
        let shotFilter = SCContentFilter(display: display, excludingWindows: [])
        if let img = try? await SCScreenshotManager.captureImage(contentFilter: shotFilter, configuration: shotCfg) {
            write(img, to: "D-screen.png")
            print("\n   wrote D-screen.png — what the menu bar looks like with the overlay up")
        }

        try? await Task.sleep(nanoseconds: 300_000_000)
        overlay?.orderOut(nil)
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
