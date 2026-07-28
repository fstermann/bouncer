// Spike 2d — corrected pivot test.
//
// 2c measured nothing: its baseline read 0% too, so per-window capture was already failing
// for reasons unrelated to the cover, and `SCContentFilter(display:including:)` fails
// outright on this OS. The filter that demonstrably works is display-scoped with
// `excludingWindows:` — which is the shape we would ship anyway: one capture over the
// status strip, sliced locally by each item's known frame.
//
// That reframes the occlusion question usefully. Excluding our own cover from the capture
// asks the compositor to render the scene *without* it, so the items underneath should be
// drawn even though a user looking at the screen cannot see them.
//
// Ladder, so a failure lands somewhere specific:
//   1. Full menu bar capture               — does capture work at all right now?
//   2. Strip capture, nothing covering     — the baseline, sliced per item
//   3. Strip capture, cover up, not excluded  — expect the cover
//   4. Strip capture, cover up, excluded      — the money shot

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

/// Ink, not alpha: a display-scoped capture has an opaque background, so "did we get the
/// item" is about whether anything was drawn, not about transparency.
func ink(_ image: CGImage?) -> Int {
    guard let image, let data = image.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else { return -1 }
    let w = image.width, h = image.height, bpr = image.bytesPerRow, bpp = image.bitsPerPixel / 8
    var lit = 0, total = 0
    for y in stride(from: 0, to: h, by: max(1, h / 24)) {
        for x in stride(from: 0, to: w, by: max(1, w / 24)) {
            let p = ptr + y * bpr + x * bpp
            let b = Int(p[0]), g = Int(p[1]), r = Int(p[2])
            let a = bpp >= 4 ? Int(p[3]) : 255
            if a > 16 && r + g + b > 90 { lit += 1 }
            total += 1
        }
    }
    return total > 0 ? lit * 100 / total : -1
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
        freopen(outDir.appendingPathComponent("occlusion3.log").path, "w", stdout)
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
        w.backgroundColor = NSColor.systemPink.withAlphaComponent(0.99)
        w.orderFrontRegardless()
        return w
    }

    func run() async {
        guard CGPreflightScreenCaptureAccess() else {
            print("not granted"); CGRequestScreenCaptureAccess(); NSApp.terminate(nil); return
        }
        print("displays asleep: \(CGDisplayIsAsleep(CGMainDisplayID()) != 0), screens: \(NSScreen.screens.count)")

        let items = statusItems().filter { $0.frame.minX >= 0 }
        guard !items.isEmpty else { print("no on-screen items"); NSApp.terminate(nil); return }
        let strip = items.dropFirst().reduce(items[0].frame) { $0.union($1.frame) }
        print("On-screen items: \(items.count), strip x=\(Int(strip.minX)) w=\(Int(strip.width))\n")

        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false),
              let display = content.displays.first
        else { print("no content"); NSApp.terminate(nil); return }

        /// One capture over the strip, then sliced per item — the shape the real bar needs.
        func captureStrip(excluding excluded: [SCWindow], label: String) async -> CGImage? {
            let cfg = SCStreamConfiguration()
            cfg.sourceRect = strip
            cfg.width = Int(strip.width * 2)
            cfg.height = Int(strip.height * 2)
            cfg.showsCursor = false
            cfg.captureResolution = .best
            let filter = SCContentFilter(display: display, excludingWindows: excluded)
            guard let img = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
            else { print("   \(label): FAILED"); return nil }
            write(img, to: "F-\(label).png")
            print("   \(label): \(img.width)x\(img.height) ink=\(ink(img))%")
            return img
        }

        // 1. Does capture work at all right now?
        let fullCfg = SCStreamConfiguration()
        fullCfg.sourceRect = CGRect(x: 0, y: 0, width: CGFloat(display.width), height: 40)
        fullCfg.width = display.width * 2
        fullCfg.height = 80
        fullCfg.showsCursor = false
        if let img = try? await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(display: display, excludingWindows: []), configuration: fullCfg) {
            write(img, to: "F-menubar.png")
            print("1. Full menu bar: \(img.width)x\(img.height) ink=\(ink(img))%")
        } else {
            print("1. Full menu bar: FAILED — capture is broken right now, later steps mean nothing")
        }

        // 2. Baseline
        print("2. Strip, uncovered")
        let baseline = await captureStrip(excluding: [], label: "uncovered")
        let baselineInk = ink(baseline)

        // 3 + 4. Cover up, captured with and without excluding it
        cover = makeCover(covering: strip)
        try? await Task.sleep(nanoseconds: 600_000_000)

        let fresh = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let coverWindow = fresh?.windows.first { $0.windowID == CGWindowID(cover?.windowNumber ?? -1) }
        print("   (cover window found in shareable content: \(coverWindow != nil))")

        print("3. Strip, covered, cover NOT excluded")
        _ = await captureStrip(excluding: [], label: "covered-included")

        print("4. Strip, covered, cover excluded from the render")
        let unmasked = await captureStrip(excluding: coverWindow.map { [$0] } ?? [], label: "covered-excluded")
        let unmaskedInk = ink(unmasked)

        cover?.orderOut(nil)
        cover = nil

        print("")
        if baselineInk > 0 && unmaskedInk >= baselineInk - 3 {
            print("VERDICT: items stay capturable underneath the cover (\(baselineInk)% → \(unmaskedInk)%).")
            print("Hiding by covering is viable — items never leave the display.")
        } else {
            print("VERDICT: cover suppresses the items (\(baselineInk)% → \(unmaskedInk)%).")
            print("Capture needs genuine visibility; the bar must be fed from a cache.")
        }

        // Timing of the shape we would actually ship.
        var samples: [Double] = []
        let cfg = SCStreamConfiguration()
        cfg.sourceRect = strip
        cfg.width = Int(strip.width * 2); cfg.height = Int(strip.height * 2)
        cfg.showsCursor = false
        let filter = SCContentFilter(display: display, excludingWindows: [])
        for _ in 0..<40 {
            let t0 = DispatchTime.now().uptimeNanoseconds
            _ = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)
        }
        samples.sort()
        print(String(format: "\nStrip capture cost: median %.2f ms, p10 %.2f, p90 %.2f (40 runs, %d items in one shot)",
                     samples[20], samples[4], samples[36], items.count))

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
