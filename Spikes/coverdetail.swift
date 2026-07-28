// Spike 9 — does the sampled cover survive a detailed background?
//
// Spike 8 scored the sampled cover at 0.00 mean difference, but it was measured against a
// solid-colour desktop. On a flat background a cover cannot fail: misalignment, scaling
// error and colour-space drift all produce the same grey. The result was real but proved
// much less than it appeared to.
//
// So this puts high-frequency content *behind* the menu bar — the bar is translucent, so a
// normal-level window under it stresses the sample exactly like a photo wallpaper would,
// without touching the user's desktop. Diagonal stripes at pixel scale plus a colour
// gradient will expose:
//
//   - a half-pixel offset, as a visible beat pattern in the difference
//   - a wrong scale factor, the same way
//   - colour-space or gamma drift on the capture → paint round trip, as a constant bias
//
// Then it answers the question spike 8 could not raise at all: how wrong does a sampled
// cover go when the content behind the menu bar changes while the cover is still up?

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

/// Mean and worst absolute difference, plus signed bias — a constant bias points at colour
/// space or gamma, while a high worst with low bias points at alignment.
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

/// Diagonal one-pixel stripes over a colour gradient: about as hostile to a resampling bug
/// as a real wallpaper ever gets.
func detailedBackdrop(width: Int, height: Int, phase: Int) -> CGImage? {
    guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                              bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    guard let data = ctx.data else { return nil }
    let ptr = data.assumingMemoryBound(to: UInt8.self)
    for y in 0..<height {
        for x in 0..<width {
            let i = y * ctx.bytesPerRow + x * 4
            let stripe: UInt8 = ((x + y + phase) % 2 == 0) ? 235 : 20
            ptr[i] = UInt8(min(255, x * 255 / max(width - 1, 1)))          // R gradient
            ptr[i + 1] = stripe                                             // G stripes
            ptr[i + 2] = UInt8(min(255, y * 255 / max(height - 1, 1)))      // B gradient
            ptr[i + 3] = 255
        }
    }
    return ctx.makeImage()
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

/// AppKit constrains any window it can out of the menu bar band — which put the backdrop
/// below the bar rather than behind it, and made the first run of this spike vacuous.
/// Refusing the constraint is the only reliable way to place a window under the menu bar.
final class UnconstrainedWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

@MainActor
final class Spike: NSObject, NSApplicationDelegate {
    var backdrop: NSWindow?
    var backdropView: NSImageView?
    var cover: NSWindow?

    func applicationDidFinishLaunching(_ n: Notification) {
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        freopen(outDir.appendingPathComponent("coverdetail.log").path, "w", stdout)
        setvbuf(stdout, nil, _IOLBF, 0)
        Task { await self.run() }
    }

    /// A normal-level window sitting under the menu bar, so its content shows through the
    /// translucency the same way a wallpaper does.
    func showBackdrop(under rect: CGRect, phase: Int) {
        let screen = NSScreen.main!
        let frame = CGRect(x: rect.minX, y: screen.frame.height - rect.maxY,
                           width: rect.width, height: rect.height)
        let image = detailedBackdrop(width: Int(rect.width * 2), height: Int(rect.height * 2), phase: phase)

        if let view = backdropView, let image {
            view.image = NSImage(cgImage: image, size: frame.size)
            return
        }
        let w = UnconstrainedWindow(contentRect: frame, styleMask: .borderless,
                                    backing: .buffered, defer: false)
        // Below the menu bar's own level (24) so the bar composites over it, above normal
        // windows so nothing else intrudes on the measurement.
        w.level = .floating
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        w.ignoresMouseEvents = true
        let view = NSImageView(frame: CGRect(origin: .zero, size: frame.size))
        if let image { view.image = NSImage(cgImage: image, size: frame.size) }
        view.imageScaling = .scaleAxesIndependently
        view.autoresizingMask = [.width, .height]
        w.contentView = view
        w.orderFrontRegardless()
        // Re-assert after ordering front: the constraint is applied on display.
        w.setFrame(frame, display: true)
        backdrop = w
        backdropView = view
    }

    func showCover(_ sample: CGImage, over rect: CGRect) {
        let screen = NSScreen.main!
        let frame = CGRect(x: rect.minX, y: screen.frame.height - rect.maxY,
                           width: rect.width, height: rect.height)
        let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        w.ignoresMouseEvents = true
        w.isOpaque = true
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

        let items = statusItems()
        guard let leftmost = items.first else { print("no items"); NSApp.terminate(nil); return }
        let region = CGRect(x: leftmost.minX - 254 - 24, y: 0, width: 254, height: 33)
        print("Region under test: x=\(Int(region.minX)) w=\(Int(region.width))\n")

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

        // ---- 1. Flat desktop, as spike 8 measured it ----
        guard let flatRef = await captureRegion() else { print("capture failed"); NSApp.terminate(nil); return }
        showCover(flatRef, over: region)
        try? await Task.sleep(nanoseconds: 900_000_000)
        if let shot = await captureRegion(), let d = difference(flatRef, shot) {
            print(String(format: "1. Flat background:     mean %.2f  worst %3d  bias %+.2f", d.mean, d.worst, d.bias))
        }
        cover?.orderOut(nil); cover = nil
        try? await Task.sleep(nanoseconds: 400_000_000)

        // ---- 2. Detailed background behind the translucent bar ----
        showBackdrop(under: region, phase: 0)
        try? await Task.sleep(nanoseconds: 900_000_000)
        guard let detailRef = await captureRegion() else { print("capture failed"); NSApp.terminate(nil); return }
        write(detailRef, to: "L-detail-reference.png")

        // The whole point is a non-uniform background. If the reference is flat, the
        // backdrop is not behind the bar and every number below would be meaningless.
        if let flat = difference(flatRef, detailRef), flat.mean < 2 {
            print("   backdrop did not reach the menu bar (diff vs flat: "
                  + String(format: "%.2f", flat.mean) + ") — numbers below would be vacuous")
            backdrop?.orderOut(nil); NSApp.terminate(nil); return
        }

        showCover(detailRef, over: region)
        try? await Task.sleep(nanoseconds: 900_000_000)
        guard let detailShot = await captureRegion(), let d2 = difference(detailRef, detailShot) else {
            print("capture failed"); NSApp.terminate(nil); return
        }
        write(detailShot, to: "L-detail-covered.png")
        print(String(format: "2. Detailed background: mean %.2f  worst %3d  bias %+.2f", d2.mean, d2.worst, d2.bias))
        print("   " + (d2.mean < 1
                       ? "→ holds: the sample is the real pixels, not an average"
                       : d2.bias > 2 || d2.bias < -2
                         ? "→ constant bias: colour space or gamma drift on the round trip"
                         : "→ alignment or scaling error, visible only on detail"))

        // ---- 3. Staleness: the background moves while the cover is still up ----
        showBackdrop(under: region, phase: 1)
        try? await Task.sleep(nanoseconds: 900_000_000)
        if let movedShot = await captureRegion() {
            write(movedShot, to: "L-detail-stale.png")
            // The cover is unchanged; the world behind it is not. Compare what the user now
            // sees against what an up-to-date cover would show.
            cover?.orderOut(nil); cover = nil
            try? await Task.sleep(nanoseconds: 500_000_000)
            if let freshRef = await captureRegion(), let d3 = difference(freshRef, movedShot) {
                print(String(format: "\n3. Stale cover after the background changed: mean %.2f  worst %3d",
                             d3.mean, d3.worst))
                print("   → " + (d3.mean < 1
                                 ? "harmless"
                                 : "the cover must be refreshed when content behind the bar moves"))
            }
        }

        backdrop?.orderOut(nil)
        cover?.orderOut(nil)
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
