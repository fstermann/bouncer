// Spike 8 — judge the cover numerically instead of by eye.
//
// The claim that display capture omits the menu bar was formed from captures taken while a
// fullscreen window was up — the same mistake that produced the wrong occlusion verdict.
// Worth retesting: if the menu bar does appear in a display capture, the cover can be
// measured rather than eyeballed.
//
// The measurement needs no hidden items and no interaction. Take an *empty* stretch of
// menu bar, capture it, then put each cover variant over that same stretch and capture
// again. A cover that is indistinguishable from empty menu bar scores a mean pixel
// difference of zero. Anything that reads as a patch stuck on top scores high.
//
// Includes a sampled variant — the captured strip painted straight back — which should be
// exact by construction and is the fallback if the materials all miss.

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

/// Mean absolute difference per channel, 0–255. Also reports the worst pixel, because a
/// cover can average well and still show a visible edge.
func difference(_ a: CGImage, _ b: CGImage) -> (mean: Double, worst: Int)? {
    guard a.width == b.width, a.height == b.height,
          let pa = pixels(a), let pb = pixels(b) else { return nil }
    var sum = 0.0, worst = 0, n = 0
    for i in stride(from: 0, to: pa.count, by: 4) {
        for c in 0..<3 {
            let d = abs(Int(pa[i + c]) - Int(pb[i + c]))
            sum += Double(d); worst = max(worst, d); n += 1
        }
    }
    return (sum / Double(max(n, 1)), worst)
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

enum Style: String, CaseIterable {
    case clear = "transparent (control, should be ~0)"
    case menu = "NSVisualEffectView .menu"
    case header = "NSVisualEffectView .headerView"
    case titlebar = "NSVisualEffectView .titlebar"
    case windowBackground = "solid windowBackgroundColor"
    case sampled = "sampled: the captured strip painted back"
}

@MainActor
final class Spike: NSObject, NSApplicationDelegate {
    var cover: NSWindow?

    func applicationDidFinishLaunching(_ n: Notification) {
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        freopen(outDir.appendingPathComponent("cover.log").path, "w", stdout)
        setvbuf(stdout, nil, _IOLBF, 0)
        Task { await self.run() }
    }

    func show(_ style: Style, over rect: CGRect, sample: CGImage?) {
        let screen = NSScreen.main!
        let frame = CGRect(x: rect.minX, y: screen.frame.height - rect.maxY,
                           width: rect.width, height: rect.height)
        let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        w.ignoresMouseEvents = true
        w.isOpaque = false
        w.backgroundColor = .clear

        func effect(_ m: NSVisualEffectView.Material) -> NSVisualEffectView {
            let v = NSVisualEffectView(frame: CGRect(origin: .zero, size: frame.size))
            v.material = m
            v.blendingMode = .behindWindow
            v.state = .active
            v.autoresizingMask = [.width, .height]
            return v
        }

        switch style {
        case .clear: break
        case .menu: w.contentView = effect(.menu)
        case .header: w.contentView = effect(.headerView)
        case .titlebar: w.contentView = effect(.titlebar)
        case .windowBackground:
            w.isOpaque = true
            w.backgroundColor = .windowBackgroundColor
        case .sampled:
            guard let sample else { break }
            let view = NSImageView(frame: CGRect(origin: .zero, size: frame.size))
            view.image = NSImage(cgImage: sample, size: frame.size)
            view.imageScaling = .scaleAxesIndependently
            view.autoresizingMask = [.width, .height]
            w.contentView = view
        }
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

        // An empty stretch of menu bar: immediately left of the leftmost status item, so it
        // is in the same visual region but has nothing drawn in it.
        let items = statusItems()
        guard let leftmost = items.first else { print("no items"); NSApp.terminate(nil); return }
        let width: CGFloat = 254
        let region = CGRect(x: leftmost.minX - width - 24, y: 0, width: width, height: 33)
        print("Empty menu bar region under test: x=\(Int(region.minX)) w=\(Int(region.width))")
        print("(leftmost status item at x=\(Int(leftmost.minX)))\n")

        func captureRegion() async -> CGImage? {
            let cfg = SCStreamConfiguration()
            cfg.sourceRect = region
            cfg.width = Int(region.width * 2)
            cfg.height = Int(region.height * 2)
            cfg.showsCursor = false
            cfg.captureResolution = .best
            return try? await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(display: display, excludingWindows: []), configuration: cfg)
        }

        guard let reference = await captureRegion() else {
            print("Display capture failed — cannot judge covers automatically."); NSApp.terminate(nil); return
        }
        write(reference, to: "K-reference.png")

        // Is the menu bar actually in this capture, or uniformly blank as before?
        if let px = pixels(reference) {
            var min0 = 255, max0 = 0
            for i in stride(from: 0, to: px.count, by: 4) {
                min0 = Swift.min(min0, Int(px[i])); max0 = Swift.max(max0, Int(px[i]))
            }
            print("Reference capture: \(reference.width)x\(reference.height), "
                  + "red channel range \(min0)–\(max0)")
            print(max0 - min0 < 4
                  ? "  → flat: the menu bar is still not in display captures. Judging by eye is the only option.\n"
                  : "  → has real content: the menu bar IS captured. Covers can be measured.\n")
        }

        print("Variant                                     mean diff   worst   verdict")
        for style in Style.allCases {
            show(style, over: region, sample: style == .sampled ? reference : nil)
            try? await Task.sleep(nanoseconds: 900_000_000)
            let shot = await captureRegion()
            cover?.orderOut(nil); cover = nil
            try? await Task.sleep(nanoseconds: 400_000_000)

            guard let shot else { print("   \(style.rawValue): capture failed"); continue }
            write(shot, to: "K-\(String(describing: style)).png")
            guard let d = difference(reference, shot) else { print("   \(style.rawValue): size mismatch"); continue }
            let verdict = d.mean < 1 ? "invisible" : d.mean < 6 ? "very close" : d.mean < 20 ? "noticeable" : "obvious patch"
            print("   " + style.rawValue.padding(toLength: 42, withPad: " ", startingAt: 0)
                  + String(format: "%6.2f   %5d   %@", d.mean, d.worst, verdict))
        }

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
