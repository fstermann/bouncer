// Spike 2f — why did capture work once and never again?
//
// The first spike captured a status item cleanly. Every spike since has returned fully
// transparent images for the same windows, and the machine is not locked, asleep, or in a
// fullscreen space, and the menu bar is on screen. The one structural difference is that
// the first spike was a bare CLI, while the later ones run an NSApplication as an
// accessory app.
//
// So: capture the same probe twice in one process — once before NSApplication exists, once
// after it is running — and print both. Whichever way it falls, it is one approval and the
// answer is unambiguous.

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

func ink(_ image: CGImage?) -> String {
    guard let image, let data = image.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else { return "nil" }
    let w = image.width, h = image.height, bpr = image.bytesPerRow, bpp = image.bitsPerPixel / 8
    var lit = 0, total = 0
    for y in 0..<h {
        for x in 0..<w {
            let p = ptr + y * bpr + x * bpp
            if (bpp >= 4 ? Int(p[3]) : 255) > 24 { lit += 1 }
            total += 1
        }
    }
    return "\(w)x\(h) ink=\(total > 0 ? lit * 100 / total : -1)%"
}

struct Item { let windowID: CGWindowID; let frame: CGRect }

func statusItems() -> [Item] {
    let opts = CGWindowListOption(arrayLiteral: .optionAll, .excludeDesktopElements)
    guard let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return [] }
    return raw.compactMap { d -> Item? in
        guard d[kCGWindowLayer as String] as? Int == 25,
              let bd = d[kCGWindowBounds as String] as? [String: Any],
              let r = CGRect(dictionaryRepresentation: bd as CFDictionary),
              r.minY == 0, r.height <= 40, r.width < 300, r.minX >= 0 else { return nil }
        return Item(windowID: CGWindowID(d[kCGWindowNumber as String] as? Int ?? 0), frame: r)
    }.sorted { $0.frame.minX < $1.frame.minX }
}

func captureAll(_ tag: String) async {
    let items = statusItems()
    guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
    else { print("[\(tag)] no shareable content"); return }
    let byID = Dictionary(uniqueKeysWithValues: content.windows.map { ($0.windowID, $0) })
    print("[\(tag)] \(items.count) items, \(content.windows.count) shareable windows, "
          + "\(content.displays.count) displays")

    for item in items.prefix(3) {
        guard let win = byID[item.windowID] else { print("[\(tag)] x=\(Int(item.frame.minX)) not shareable"); continue }
        let cfg = SCStreamConfiguration()
        cfg.width = Int(win.frame.width * 2)
        cfg.height = Int(win.frame.height * 2)
        cfg.showsCursor = false
        let img = try? await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: win), configuration: cfg)
        print("[\(tag)] x=\(Int(item.frame.minX)) w=\(Int(item.frame.width)) → \(ink(img))")
        if let img { write(img, to: "H-\(tag)-\(Int(item.frame.minX)).png") }
    }

    // The menu bar itself, for reference: if this is blank too, nothing system-drawn is
    // reaching us and the problem is the grant, not the item windows.
    if let display = content.displays.first {
        let cfg = SCStreamConfiguration()
        cfg.sourceRect = CGRect(x: 0, y: 0, width: CGFloat(display.width), height: 33)
        cfg.width = display.width; cfg.height = 33
        cfg.showsCursor = false
        let img = try? await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(display: display, excludingWindows: []), configuration: cfg)
        print("[\(tag)] whole menu bar → \(ink(img))")
        if let img { write(img, to: "H-\(tag)-menubar.png") }
    }
}

// ---- Phase 1: before NSApplication exists ----
let sema = DispatchSemaphore(value: 0)
Task {
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    freopen(outDir.appendingPathComponent("ab.log").path, "w", stdout)
    setvbuf(stdout, nil, _IOLBF, 0)
    guard CGPreflightScreenCaptureAccess() else {
        print("not granted")
        CGRequestScreenCaptureAccess()
        exit(0)
    }
    print("=== phase 1: bare process, no NSApplication ===")
    await captureAll("bare")
    sema.signal()
}
sema.wait()

// ---- Phase 2: same process, now a running accessory NSApplication ----
@MainActor
final class Delegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ note: Notification) {
        Task {
            print("\n=== phase 2: NSApplication running, .accessory ===")
            await captureAll("nsapp")
            print("\ndone")
            NSApp.terminate(nil)
        }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = Delegate()
    app.delegate = delegate
    objc_setAssociatedObject(app, "d", delegate, .OBJC_ASSOCIATION_RETAIN)
    app.setActivationPolicy(.accessory)
    app.run()
}
