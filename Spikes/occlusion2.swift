// Spike 2c — can we hide items from the eye without hiding them from the compositor?
//
// Spike 2b showed a fully opaque cover blanks the items: the window server culls surfaces
// it believes nobody can see. Culling is an occlusion optimisation, and it can only be
// applied when the occluder is genuinely opaque. A cover at 99% alpha is visually
// indistinguishable and formally translucent, so the compositor must keep drawing what is
// underneath — which would leave the items capturable while invisible.
//
// If a variant below keeps opaque% at its uncovered value, the standalone bar is buildable
// with items left in place. If they all read 0%, capture requires genuine visibility and
// the bar has to be fed from a cache refreshed while the items are on screen.
//
// Also retries the strip capture, which failed in 2b for reasons unrelated to occlusion.

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

func opaquePercent(_ image: CGImage?) -> Int {
    guard let image, let data = image.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else { return -1 }
    let w = image.width, h = image.height, bpr = image.bytesPerRow, bpp = image.bitsPerPixel / 8
    var opaque = 0, total = 0
    for y in stride(from: 0, to: h, by: max(1, h / 16)) {
        for x in stride(from: 0, to: w, by: max(1, w / 16)) {
            let p = ptr + y * bpr + x * bpp
            if (bpp >= 4 ? Int(p[3]) : 255) > 16 { opaque += 1 }
            total += 1
        }
    }
    return total > 0 ? opaque * 100 / total : -1
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

enum Variant: String, CaseIterable {
    case opaqueControl = "opaque (control)"
    case backgroundAlpha99 = "isOpaque=false, bg alpha .99"
    case windowAlpha99 = "isOpaque=false, alphaValue .99"
    case windowAlpha999 = "isOpaque=false, alphaValue .999"
}

@MainActor
final class Spike: NSObject, NSApplicationDelegate {
    var overlay: NSWindow?

    func applicationDidFinishLaunching(_ note: Notification) {
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        freopen(outDir.appendingPathComponent("occlusion2.log").path, "w", stdout)
        setvbuf(stdout, nil, _IOLBF, 0)
        Task { await self.run() }
    }

    func show(_ variant: Variant, covering rect: CGRect) {
        let screen = NSScreen.main!
        let frame = CGRect(x: rect.minX, y: screen.frame.height - rect.maxY,
                           width: rect.width, height: rect.height)
        let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        switch variant {
        case .opaqueControl:
            w.isOpaque = true
            w.backgroundColor = .black
        case .backgroundAlpha99:
            w.isOpaque = false
            w.backgroundColor = NSColor.black.withAlphaComponent(0.99)
        case .windowAlpha99:
            w.isOpaque = false
            w.backgroundColor = .black
            w.alphaValue = 0.99
        case .windowAlpha999:
            w.isOpaque = false
            w.backgroundColor = .black
            w.alphaValue = 0.999
        }
        w.orderFrontRegardless()
        overlay = w
    }

    func run() async {
        guard CGPreflightScreenCaptureAccess() else {
            print("not granted"); CGRequestScreenCaptureAccess(); NSApp.terminate(nil); return
        }
        let items = statusItems().filter { $0.frame.minX >= 0 }
        guard let probe = items.first else { print("no items"); NSApp.terminate(nil); return }
        let strip = items.dropFirst().reduce(items[0].frame) { $0.union($1.frame) }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false),
              let display = content.displays.first
        else { print("no content"); NSApp.terminate(nil); return }
        let byID = Dictionary(uniqueKeysWithValues: content.windows.map { ($0.windowID, $0) })
        guard let scProbe = byID[probe.windowID] else { print("probe missing"); NSApp.terminate(nil); return }

        func captureProbe() async -> CGImage? {
            let cfg = SCStreamConfiguration()
            cfg.width = Int(scProbe.frame.width * 2)
            cfg.height = Int(scProbe.frame.height * 2)
            cfg.showsCursor = false
            return try? await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: scProbe), configuration: cfg)
        }

        let baseline = opaquePercent(await captureProbe())
        print("Probe win \(probe.windowID) x=\(Int(probe.frame.minX)) — uncovered opaque=\(baseline)%\n")
        print("Overlay variant                        opaque%   verdict")

        for variant in Variant.allCases {
            show(variant, covering: strip)
            try? await Task.sleep(nanoseconds: 500_000_000)
            let pct = opaquePercent(await captureProbe())
            overlay?.orderOut(nil)
            overlay = nil
            try? await Task.sleep(nanoseconds: 200_000_000)
            let verdict = pct >= baseline - 2 ? "SURVIVES — still composited" : "culled"
            print("\(variant.rawValue.padding(toLength: 38, withPad: " ", startingAt: 0))\(pct)%".padding(toLength: 48, withPad: " ", startingAt: 0) + verdict)
        }

        // ---- Strip capture, retried without the flags that may have broken it in 2b ----
        print("\nStrip capture variants (x=\(Int(strip.minX)) w=\(Int(strip.width)))")
        let scItems = items.compactMap { byID[$0.windowID] }

        func timeCapture(_ label: String, _ make: () -> (SCContentFilter, SCStreamConfiguration)) async {
            let (filter, cfg) = make()
            guard let img = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
            else { print("   \(label): FAILED"); return }
            write(img, to: "E-\(label.replacingOccurrences(of: " ", with: "-")).png")
            var samples: [Double] = []
            for _ in 0..<30 {
                let t0 = DispatchTime.now().uptimeNanoseconds
                _ = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
                samples.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)
            }
            samples.sort()
            print(String(format: "   %@: %dx%d opaque=%d%%, median %.2f ms (min %.2f max %.2f)",
                         label, img.width, img.height, opaquePercent(img),
                         samples[15], samples.first ?? 0, samples.last ?? 0))
        }

        await timeCapture("display-including-items, sourceRect") {
            let cfg = SCStreamConfiguration()
            cfg.sourceRect = strip
            cfg.width = Int(strip.width * 2); cfg.height = Int(strip.height * 2)
            cfg.showsCursor = false
            return (SCContentFilter(display: display, including: scItems), cfg)
        }
        await timeCapture("display-including-items, no sourceRect") {
            let cfg = SCStreamConfiguration()
            cfg.showsCursor = false
            return (SCContentFilter(display: display, including: scItems), cfg)
        }
        await timeCapture("single window") {
            let cfg = SCStreamConfiguration()
            cfg.width = Int(scProbe.frame.width * 2); cfg.height = Int(scProbe.frame.height * 2)
            cfg.showsCursor = false
            return (SCContentFilter(desktopIndependentWindow: scProbe), cfg)
        }

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
