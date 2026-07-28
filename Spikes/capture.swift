// Spike 2 + 3 — can we get pixels for a status item that is off screen, and how fast?
//
// This is the make-or-break spike for the standalone bar. Hidden items are pushed past the
// left edge of the display by an expanded divider. If the window server does not composite
// them there, no capture pipeline can replicate them and the whole feature needs a
// different mechanism (reveal-then-capture-then-rehide, which would be visibly janky).
//
// Compares:
//   A. CGWindowListCreateImage per window          (deprecated since 14.0, may be gutted)
//   B. SCScreenshotManager per window              (desktopIndependentWindow filter)
//   C. SCScreenshotManager once over the whole strip, sliced locally
//
// Build: swiftc -O -parse-as-library Spikes/capture.swift -o Spikes/.bin/capture
// Run:   Spikes/.bin/capture [iterations]

import AppKit
import ScreenCaptureKit
import UniformTypeIdentifiers

// CGWindowListCreateImage was *obsoleted* in the macOS 15 SDK, so it cannot be called
// directly any more. It is still in the dylib, and it is the API every existing menu bar
// manager was built on — so the spike reaches it through dlsym purely to measure what we
// would be giving up. Nothing here argues for shipping it.
typealias WindowListCreateImage = @convention(c) (CGRect, CGWindowListOption, CGWindowID, CGWindowImageOption) -> Unmanaged<CGImage>?
let legacyCapture: WindowListCreateImage? = dlsym(
    dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY),
    "CGWindowListCreateImage"
).map { unsafeBitCast($0, to: WindowListCreateImage.self) }

// MARK: - Status item discovery (no permission needed, per spike 1)

struct Item {
    let windowID: CGWindowID
    let pid: pid_t
    let frame: CGRect  // CG coordinates: top-left origin
    var isOffScreen: Bool
    /// Bouncer's expanded divider is thousands of points wide; a real item never is.
    var looksLikeDivider: Bool { frame.width > 300 }
}

func statusItems() -> [Item] {
    let opts = CGWindowListOption(arrayLiteral: .optionAll, .excludeDesktopElements)
    guard let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
        return []
    }
    let screens = NSScreen.screens.map(\.frame)
    let menuBarHeight = (NSScreen.main?.frame.height ?? 0) - (NSScreen.main?.visibleFrame.maxY ?? 0)

    return raw.compactMap { d -> Item? in
        guard d[kCGWindowLayer as String] as? Int == 25,
              let boundsDict = d[kCGWindowBounds as String] as? [String: Any],
              let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
              rect.minY == 0, rect.height <= max(menuBarHeight, 40)
        else { return nil }
        let onAScreen = screens.contains { $0.intersects(CGRect(x: rect.midX, y: 0, width: 1, height: 1)) }
        return Item(
            windowID: CGWindowID(d[kCGWindowNumber as String] as? Int ?? 0),
            pid: pid_t(d[kCGWindowOwnerPID as String] as? Int ?? 0),
            frame: rect,
            isOffScreen: !onAScreen
        )
    }
    .sorted { $0.frame.minX < $1.frame.minX }
}

// MARK: - Helpers

/// Anchored to the bundle: launched through LaunchServices — which is what gives the
/// spike its own TCC identity — the working directory is `/`.
let outDir: URL = {
    let bundle = Bundle.main.bundleURL
    return bundle.pathExtension == "app"
        ? bundle.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("out")
        : URL(fileURLWithPath: "Spikes/out")
}()

func write(_ image: CGImage, to name: String) {
    let dir = outDir
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent(name)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

/// A capture of an off-screen window may "succeed" and hand back transparent or black
/// pixels. Only a non-trivial spread of alpha and luminance means we actually got the item.
func describe(_ image: CGImage?) -> String {
    guard let image else { return "nil" }
    let w = image.width, h = image.height
    guard let data = image.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else {
        return "\(w)x\(h) (no data)"
    }
    let bpr = image.bytesPerRow, bpp = image.bitsPerPixel / 8
    var opaque = 0, nonBlack = 0, total = 0
    for y in stride(from: 0, to: h, by: max(1, h / 16)) {
        for x in stride(from: 0, to: w, by: max(1, w / 16)) {
            let p = ptr + y * bpr + x * bpp
            let b = Int(p[0]), g = Int(p[1]), r = Int(p[2])
            let a = bpp >= 4 ? Int(p[3]) : 255
            if a > 16 { opaque += 1 }
            if r + g + b > 24 { nonBlack += 1 }
            total += 1
        }
    }
    let pctOpaque = total > 0 ? opaque * 100 / total : 0
    let pctInk = total > 0 ? nonBlack * 100 / total : 0
    return "\(w)x\(h) opaque=\(pctOpaque)% nonBlack=\(pctInk)%"
}

func time(_ n: Int, _ body: () -> Void) -> (median: Double, min: Double, max: Double) {
    var samples: [Double] = []
    for _ in 0..<n {
        let t0 = DispatchTime.now().uptimeNanoseconds
        body()
        samples.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)
    }
    samples.sort()
    return (samples[samples.count / 2], samples.first ?? 0, samples.last ?? 0)
}

// MARK: - Main

@main
enum Spike {
    static func main() async {
        let iterations = Int(CommandLine.arguments.dropFirst().first ?? "") ?? 30
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        // No terminal is attached when LaunchServices starts us.
        freopen(outDir.appendingPathComponent("capture.log").path, "w", stdout)
        setvbuf(stdout, nil, _IOLBF, 0)
        defer { fflush(stdout) }

        guard CGPreflightScreenCaptureAccess() else {
            print("Screen Recording permission NOT granted for this process.")
            print("Requesting it now — approve the dialog, then re-run this spike.")
            CGRequestScreenCaptureAccess()
            return
        }
        print("Screen Recording: granted\n")

        let items = statusItems()
        let real = items.filter { !$0.looksLikeDivider }
        let hidden = real.filter(\.isOffScreen)
        let visible = real.filter { !$0.isOffScreen }
        print("Status items: \(real.count) real (\(hidden.count) off screen, \(visible.count) on screen), "
              + "\(items.count - real.count) divider(s)")
        guard let probeHidden = hidden.first, let probeVisible = visible.first else {
            print("Need at least one hidden and one visible item. Is Bouncer collapsed?")
            return
        }
        print("Probe hidden item: win \(probeHidden.windowID) at x=\(Int(probeHidden.frame.minX))")
        print("Probe visible item: win \(probeVisible.windowID) at x=\(Int(probeVisible.frame.minX))\n")

        // ---- A. CGWindowListCreateImage (deprecated) ----
        print("A. CGWindowListCreateImage (obsoleted in the 15.0 SDK, reached via dlsym)")
        if let legacyCapture {
            for (label, item) in [("visible", probeVisible), ("hidden ", probeHidden)] {
                let img = legacyCapture(.null, .optionIncludingWindow, item.windowID,
                                        [.boundsIgnoreFraming, .bestResolution])?.takeRetainedValue()
                print("   \(label): \(describe(img))")
                if let img { write(img, to: "A-\(label.trimmingCharacters(in: .whitespaces)).png") }
            }
            let aTime = time(iterations) {
                _ = legacyCapture(.null, .optionIncludingWindow, probeHidden.windowID,
                                  [.boundsIgnoreFraming, .bestResolution])?.takeRetainedValue()
            }
            print(String(format: "   %d hidden captures: median %.2f ms (min %.2f, max %.2f)\n",
                         iterations, aTime.median, aTime.min, aTime.max))
        } else {
            print("   symbol gone from the dylib\n")
        }

        // ---- Shareable content ----
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            print("SCShareableContent failed: \(error)")
            return
        }
        let scByID = Dictionary(uniqueKeysWithValues: content.windows.map { ($0.windowID, $0) })
        let foundHidden = scByID[probeHidden.windowID] != nil
        print("B. ScreenCaptureKit")
        print("   off-screen item present in SCShareableContent: \(foundHidden)")
        print("   status-item windows visible to SCK: "
              + "\(real.filter { scByID[$0.windowID] != nil }.count)/\(real.count)")

        guard let scHidden = scByID[probeHidden.windowID], let scVisible = scByID[probeVisible.windowID] else {
            print("   cannot benchmark per-window SCK capture without both probes")
            return
        }

        for (label, win) in [("visible", scVisible), ("hidden ", scHidden)] {
            let cfg = SCStreamConfiguration()
            cfg.width = Int(win.frame.width * 2)
            cfg.height = Int(win.frame.height * 2)
            cfg.showsCursor = false
            cfg.ignoreGlobalClipDisplay = true
            let filter = SCContentFilter(desktopIndependentWindow: win)
            do {
                let img = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
                print("   \(label): \(describe(img))")
                write(img, to: "B-\(label.trimmingCharacters(in: .whitespaces)).png")
            } catch {
                print("   \(label): FAILED \(error.localizedDescription)")
            }
        }

        var scSamples: [Double] = []
        for _ in 0..<iterations {
            let cfg = SCStreamConfiguration()
            cfg.width = Int(scHidden.frame.width * 2)
            cfg.height = Int(scHidden.frame.height * 2)
            cfg.showsCursor = false
            let filter = SCContentFilter(desktopIndependentWindow: scHidden)
            let t0 = DispatchTime.now().uptimeNanoseconds
            _ = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
            scSamples.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)
        }
        scSamples.sort()
        print(String(format: "   %d hidden captures: median %.2f ms (min %.2f, max %.2f)",
                     iterations, scSamples[scSamples.count / 2], scSamples.first ?? 0, scSamples.last ?? 0))
        print(String(format: "   → whole section of %d items, one at a time: %.1f ms\n",
                     hidden.count, scSamples[scSamples.count / 2] * Double(hidden.count)))

        // ---- C. One capture over the whole off-screen strip, sliced locally ----
        // If this works it is the win: one round trip regardless of item count.
        print("C. Single capture of the whole hidden strip, sliced")
        guard let display = content.displays.first else { print("   no display"); return }
        let strip = hidden.reduce(hidden[0].frame) { $0.union($1.frame) }
        print("   strip = x=\(Int(strip.minX)) w=\(Int(strip.width)) h=\(Int(strip.height))")

        let cfg = SCStreamConfiguration()
        cfg.sourceRect = strip
        cfg.width = Int(strip.width * 2)
        cfg.height = Int(strip.height * 2)
        cfg.showsCursor = false
        cfg.ignoreGlobalClipDisplay = true
        let stripFilter = SCContentFilter(
            display: display,
            including: hidden.compactMap { scByID[$0.windowID] }
        )
        do {
            let img = try await SCScreenshotManager.captureImage(contentFilter: stripFilter, configuration: cfg)
            print("   strip: \(describe(img))")
            write(img, to: "C-strip.png")
        } catch {
            print("   strip: FAILED \(error.localizedDescription)")
        }

        var stripSamples: [Double] = []
        for _ in 0..<iterations {
            let t0 = DispatchTime.now().uptimeNanoseconds
            _ = try? await SCScreenshotManager.captureImage(contentFilter: stripFilter, configuration: cfg)
            stripSamples.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)
        }
        stripSamples.sort()
        print(String(format: "   %d strip captures: median %.2f ms (min %.2f, max %.2f)",
                     iterations, stripSamples[stripSamples.count / 2],
                     stripSamples.first ?? 0, stripSamples.last ?? 0))
        print("\nPNGs written to Spikes/out/")
    }
}
