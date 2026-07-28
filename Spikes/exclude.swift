// Spike 10 — can the cover be refreshed while the items are under it?
//
// Spike 9 settled that a sampled cover is pixel-exact on any background, and that it drifts
// badly (mean 72, worst 217) as soon as content behind the menu bar moves. So the cover
// cannot be sampled once at open; it has to track.
//
// Refreshing it means capturing the menu bar strip as it would look *without* the items —
// they are sitting right there under the cover, and a plain capture would include them,
// which would paint the items back on top of themselves.
//
// `SCContentFilter(display:excludingWindows:)` should render the scene with those windows
// omitted. If it does, the cover can be driven from a stream and stays correct no matter
// what moves behind the bar. If it does not, the cover has to be sampled during moments
// when the strip is genuinely empty, and the feature inherits a visible failure mode.

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

func meanDifference(_ a: CGImage, _ b: CGImage) -> Double? {
    guard a.width == b.width, a.height == b.height, let pa = pixels(a), let pb = pixels(b) else { return nil }
    var sum = 0.0
    var n = 0
    for i in stride(from: 0, to: pa.count, by: 4) {
        for c in 0..<3 { sum += Double(abs(Int(pa[i + c]) - Int(pb[i + c]))); n += 1 }
    }
    return sum / Double(max(n, 1))
}

/// How much the image varies internally. An empty stretch of menu bar is smooth; one with
/// glyphs in it is not. Used to tell "items were removed" from "capture returned nothing".
func contrast(_ image: CGImage) -> Double? {
    guard let px = pixels(image) else { return nil }
    var values: [Double] = []
    for i in stride(from: 0, to: px.count, by: 4) {
        values.append((Double(px[i]) + Double(px[i + 1]) + Double(px[i + 2])) / 3)
    }
    let mean = values.reduce(0, +) / Double(values.count)
    let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
    return variance.squareRoot()
}

struct Item { let windowID: CGWindowID; let frame: CGRect }

func statusItems() -> [Item] {
    let raw = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] ?? []
    return raw.compactMap { d -> Item? in
        guard d[kCGWindowLayer as String] as? Int == 25,
              let bd = d[kCGWindowBounds as String] as? [String: Any],
              let r = CGRect(dictionaryRepresentation: bd as CFDictionary),
              r.minY == 0, r.height <= 40, r.width < 300, r.minX >= 0 else { return nil }
        return Item(windowID: CGWindowID(d[kCGWindowNumber as String] as? Int ?? 0), frame: r)
    }.sorted { $0.frame.minX < $1.frame.minX }
}

@main
enum Spike {
    static func main() async {
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        freopen(outDir.appendingPathComponent("exclude.log").path, "w", stdout)
        setvbuf(stdout, nil, _IOLBF, 0)

        guard CGPreflightScreenCaptureAccess() else {
            print("not granted"); CGRequestScreenCaptureAccess(); return
        }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false),
              let display = content.displays.first
        else { print("no content"); return }

        let items = statusItems()
        guard !items.isEmpty else { print("no items"); return }
        let strip = items.dropFirst().reduce(items[0].frame) { $0.union($1.frame) }
        let byID = Dictionary(uniqueKeysWithValues: content.windows.map { ($0.windowID, $0) })
        let itemWindows = items.compactMap { byID[$0.windowID] }
        print("Strip x=\(Int(strip.minX)) w=\(Int(strip.width)) — \(items.count) items, "
              + "\(itemWindows.count) resolved as SCWindows\n")

        func capture(excluding excluded: [SCWindow]) async -> CGImage? {
            let cfg = SCStreamConfiguration()
            cfg.sourceRect = strip
            cfg.width = Int(strip.width * 2)
            cfg.height = Int(strip.height * 2)
            cfg.showsCursor = false
            cfg.captureResolution = .best
            return try? await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(display: display, excludingWindows: excluded),
                configuration: cfg)
        }

        guard let withItems = await capture(excluding: []) else { print("baseline failed"); return }
        write(withItems, to: "M-with-items.png")

        guard let withoutItems = await capture(excluding: itemWindows) else {
            print("Excluding the item windows FAILED — the cover cannot be refreshed this way.")
            return
        }
        write(withoutItems, to: "M-without-items.png")

        let diff = meanDifference(withItems, withoutItems) ?? -1
        let contrastWith = contrast(withItems) ?? -1
        let contrastWithout = contrast(withoutItems) ?? -1

        print(String(format: "with items:    contrast %.2f", contrastWith))
        print(String(format: "without items: contrast %.2f", contrastWithout))
        print(String(format: "mean difference between them: %.2f\n", diff))

        if diff < 1 {
            print("VERDICT: exclusion had no effect — the items are still in the capture.")
            print("The cover cannot track; it must be sampled while the strip is empty.")
        } else if contrastWithout < contrastWith / 2 {
            print("VERDICT: the items are gone and what is left is smooth menu bar.")
            print("The cover can be refreshed live, so it stays correct as things move behind the bar.")
        } else {
            print("VERDICT: the capture changed but is not smooth — inspect M-without-items.png.")
        }

        // Cost of one refresh, since it would run on every change behind the bar.
        var samples: [Double] = []
        for _ in 0..<20 {
            let t0 = DispatchTime.now().uptimeNanoseconds
            _ = await capture(excluding: itemWindows)
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)
        }
        samples.sort()
        print(String(format: "\nCost of one cover refresh: median %.2f ms (min %.2f, max %.2f)",
                     samples[10], samples.first ?? 0, samples.last ?? 0))
        print("\ndone")
    }
}
