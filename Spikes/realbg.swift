// Spike 11 — the cover against the real thing, with no synthetic layer.
//
// Spike 9 injected its test content at `.floating`, which sits above normal windows. That
// painted over the real windows and, more importantly, over their shadows — which stack
// under the menu bar and darken it noticeably. So the compositing order under test was not
// the one that actually occurs: the test content was in front of the shadows instead of
// behind them.
//
// The fix is to stop injecting anything. The menu bar over real windows, real shadows and
// real wallpaper is the only background that matters, so this scans the actual bar for its busiest
// stretch and runs the round trip there:
//
//     capture the region → paint it back as an opaque cover → capture again → compare
//
// If the sampled cover reproduces a shadow gradient it did not author, it reproduces
// anything. If it cannot, the whole cover approach needs rethinking rather than tuning.

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

func pixels(_ image: CGImage) -> [UInt8]? {
    let w = image.width, h = image.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return buf
}

struct Diff { let mean: Double; let worst: Int; let bias: Double }

func difference(_ a: CGImage, _ b: CGImage) -> Diff? {
    guard a.width == b.width, a.height == b.height, let pa = pixels(a), let pb = pixels(b) else { return nil }
    var sum = 0.0, signed = 0.0, worst = 0, n = 0
    for i in stride(from: 0, to: pa.count, by: 4) {
        for c in 0..<3 {
            let d = Int(pa[i + c]) - Int(pb[i + c])
            sum += Double(abs(d)); signed += Double(d); worst = max(worst, abs(d)); n += 1
        }
    }
    return Diff(mean: sum / Double(max(n, 1)), worst: worst, bias: signed / Double(max(n, 1)))
}

func standardDeviation(_ image: CGImage) -> Double {
    guard let px = pixels(image) else { return 0 }
    var values: [Double] = []
    values.reserveCapacity(px.count / 4)
    for i in stride(from: 0, to: px.count, by: 4) {
        values.append((Double(px[i]) + Double(px[i + 1]) + Double(px[i + 2])) / 3)
    }
    let mean = values.reduce(0, +) / Double(values.count)
    return (values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)).squareRoot()
}

/// A window whose frame AppKit is not allowed to push out of the menu bar band.
final class UnconstrainedWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

func statusItems() -> [CGRect] {
    let raw = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] ?? []
    return raw.compactMap { d -> CGRect? in
        guard d[kCGWindowLayer as String] as? Int == 25,
              let bd = d[kCGWindowBounds as String] as? [String: Any],
              let r = CGRect(dictionaryRepresentation: bd as CFDictionary),
              r.minY == 0, r.height <= 40, r.width < 300, r.minX >= 0 else { return nil }
        return r
    }.sorted { $0.minX < $1.minX }
}

@MainActor
final class Spike: NSObject, NSApplicationDelegate {
    var cover: NSWindow?

    func applicationDidFinishLaunching(_ n: Notification) {
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        freopen(outDir.appendingPathComponent("realbg.log").path, "w", stdout)
        setvbuf(stdout, nil, _IOLBF, 0)
        Task { await self.run() }
    }

    func showCover(_ sample: CGImage, over rect: CGRect) {
        let screen = NSScreen.main!
        let frame = CGRect(x: rect.minX, y: screen.frame.height - rect.maxY,
                           width: rect.width, height: rect.height)
        let w = UnconstrainedWindow(contentRect: frame, styleMask: .borderless,
                                    backing: .buffered, defer: false)
        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        w.ignoresMouseEvents = true
        w.isOpaque = true
        w.hasShadow = false
        let view = NSImageView(frame: CGRect(origin: .zero, size: frame.size))
        view.image = NSImage(cgImage: sample, size: frame.size)
        view.imageScaling = .scaleAxesIndependently
        view.autoresizingMask = [.width, .height]
        w.contentView = view
        w.orderFrontRegardless()
        cover = w
    }

    func run() async {
        guard CGPreflightScreenCaptureAccess() else {
            print("not granted"); CGRequestScreenCaptureAccess(); NSApp.terminate(nil); return
        }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false),
              let display = content.displays.first
        else { print("no content"); NSApp.terminate(nil); return }

        func capture(_ rect: CGRect) async -> CGImage? {
            let cfg = SCStreamConfiguration()
            cfg.sourceRect = rect
            cfg.width = Int(rect.width * 2)
            cfg.height = Int(rect.height * 2)
            cfg.showsCursor = false
            cfg.captureResolution = .best
            return try? await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(display: display, excludingWindows: []), configuration: cfg)
        }

        // Scan the bar left of the status items for the busiest 254 pt stretch — that is
        // where real windows and their stacked shadows are showing through.
        let limit = statusItems().first?.minX ?? 1200
        let width: CGFloat = 254
        var best: (rect: CGRect, sd: Double)?
        var x: CGFloat = 0
        while x + width <= limit {
            let rect = CGRect(x: x, y: 0, width: width, height: 33)
            if let img = await capture(rect) {
                let sd = standardDeviation(img)
                if best == nil || sd > best!.sd { best = (rect, sd) }
            }
            x += width / 2
        }
        guard let (region, sd) = best else { print("could not scan the bar"); NSApp.terminate(nil); return }
        print(String(format: "Busiest stretch of real menu bar: x=%d w=%d, std dev %.2f",
                     Int(region.minX), Int(region.width), sd))

        if sd < 3 {
            print("\nThe whole bar is close to uniform right now — nothing is showing through it.")
            print("Drag a window so it sits under the menu bar and run this again; otherwise")
            print("this measures the same flat case spike 8 already did.")
            NSApp.terminate(nil); return
        }

        guard let reference = await capture(region) else { print("capture failed"); NSApp.terminate(nil); return }
        write(reference, to: "N-real-reference.png")

        showCover(reference, over: region)
        try? await Task.sleep(nanoseconds: 900_000_000)
        guard let shot = await capture(region), let d = difference(reference, shot) else {
            print("capture failed"); NSApp.terminate(nil); return
        }
        write(shot, to: "N-real-covered.png")
        cover?.orderOut(nil); cover = nil

        print(String(format: "\nSampled cover over real content: mean %.2f  worst %3d  bias %+.2f",
                     d.mean, d.worst, d.bias))
        print("   → " + (d.mean < 1
                         ? "reproduces real shadows and gradients it did not author"
                         : "cannot reproduce the real bar — the cover approach needs rethinking"))
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
