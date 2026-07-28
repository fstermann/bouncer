// Spike 5 + 6 — the two things left before the bar can be built.
//
// A. STREAM LATENCY AND WORK AT REST.
//    One-shot capture costs 38 ms concurrent for 7 items, which is more than two frames —
//    too slow to open smoothly and far too slow to track a live clock. A persistent
//    SCStream should amortise that. Two things matter beyond raw latency: how long until
//    the first frame (that is the open cost), and whether frames keep arriving when
//    nothing on screen changes. If a stream only delivers on change, it is an event source
//    rather than a poll, and it fits the no-work-at-rest rule while the bar is open. If it
//    delivers 60 fps of identical frames, it is a poll wearing a costume and the CPU cost
//    has to be justified against the alternative.
//
// B. COVER FIDELITY.
//    The cover has to read as empty menu bar. It cannot be checked by screenshot, because
//    display capture does not include menu bar content on this OS — so the variants are
//    shown in turn for the user to judge by eye.

import AppKit
import ScreenCaptureKit

let outDir: URL = {
    let b = Bundle.main.bundleURL
    return b.pathExtension == "app"
        ? b.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("out")
        : URL(fileURLWithPath: "Spikes/out")
}()

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

/// Records frame arrival times, and how many frames actually differed from the previous
/// one — the number that separates an event source from a poll.
final class Recorder: NSObject, SCStreamOutput, @unchecked Sendable {
    let started = DispatchTime.now().uptimeNanoseconds
    private let lock = NSLock()
    private(set) var arrivals: [Double] = []
    private(set) var distinct = 0
    private var lastHash: Int?

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let pixels = CMSampleBufferGetImageBuffer(buffer) else { return }
        let ms = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000

        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        var hash = 0
        if let base = CVPixelBufferGetBaseAddress(pixels) {
            let bpr = CVPixelBufferGetBytesPerRow(pixels)
            let height = CVPixelBufferGetHeight(pixels)
            let ptr = base.assumingMemoryBound(to: UInt8.self)
            // Cheap content fingerprint: sample a sparse grid.
            for y in stride(from: 0, to: height, by: 4) {
                for x in stride(from: 0, to: bpr, by: 64) {
                    hash = hash &* 31 &+ Int(ptr[y * bpr + x])
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(pixels, .readOnly)

        lock.lock()
        arrivals.append(ms)
        if lastHash != hash { distinct += 1; lastHash = hash }
        lock.unlock()
    }
}

func cpuSeconds() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
        + Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
}

enum CoverStyle: String, CaseIterable {
    case menuMaterial = "NSVisualEffectView .menu"
    case headerMaterial = "NSVisualEffectView .headerView"
    case windowBackground = "solid windowBackgroundColor"
    case clear = "fully transparent (control — items visible)"
}

@MainActor
final class Spike: NSObject, NSApplicationDelegate {
    var cover: NSWindow?

    func applicationDidFinishLaunching(_ n: Notification) {
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        freopen(outDir.appendingPathComponent("stream.log").path, "w", stdout)
        setvbuf(stdout, nil, _IOLBF, 0)
        Task { await self.run() }
    }

    func showCover(_ style: CoverStyle, over rect: CGRect) {
        let screen = NSScreen.main!
        let frame = CGRect(x: rect.minX, y: screen.frame.height - rect.maxY,
                           width: rect.width, height: rect.height)
        let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        w.ignoresMouseEvents = true
        w.isOpaque = false
        w.backgroundColor = .clear

        switch style {
        case .menuMaterial, .headerMaterial:
            let effect = NSVisualEffectView(frame: CGRect(origin: .zero, size: frame.size))
            effect.material = style == .menuMaterial ? .menu : .headerView
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.autoresizingMask = [.width, .height]
            w.contentView = effect
        case .windowBackground:
            w.isOpaque = true
            w.backgroundColor = .windowBackgroundColor
        case .clear:
            break
        }
        w.orderFrontRegardless()
        cover = w
    }

    func run() async {
        guard CGPreflightScreenCaptureAccess() else {
            print("not granted"); CGRequestScreenCaptureAccess(); NSApp.terminate(nil); return
        }
        let items = statusItems()
        guard !items.isEmpty else { print("no items"); NSApp.terminate(nil); return }
        let strip = items.dropFirst().reduce(items[0].frame) { $0.union($1.frame) }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        else { print("no content"); NSApp.terminate(nil); return }
        let byID = Dictionary(uniqueKeysWithValues: content.windows.map { ($0.windowID, $0) })

        // ---- A. One persistent stream per item ----
        print("A. Persistent SCStream, one per item (\(items.count) items)\n")
        var streams: [SCStream] = []
        var recorders: [Recorder] = []
        let cpuBefore = cpuSeconds()
        let wall0 = DispatchTime.now().uptimeNanoseconds

        for item in items {
            guard let win = byID[item.windowID] else { continue }
            let cfg = SCStreamConfiguration()
            cfg.width = Int(win.frame.width * 2)
            cfg.height = Int(win.frame.height * 2)
            cfg.showsCursor = false
            cfg.queueDepth = 3
            // Ask for 60 fps; what actually arrives is the interesting part.
            cfg.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: win),
                                  configuration: cfg, delegate: nil)
            let rec = Recorder()
            do {
                try stream.addStreamOutput(rec, type: .screen,
                                           sampleHandlerQueue: DispatchQueue(label: "cap\(item.windowID)"))
                try await stream.startCapture()
                streams.append(stream)
                recorders.append(rec)
            } catch {
                print("   stream for x=\(Int(item.frame.minX)) failed: \(error.localizedDescription)")
            }
        }
        let startupMs = Double(DispatchTime.now().uptimeNanoseconds - wall0) / 1_000_000
        print("   \(streams.count) streams started in \(Int(startupMs)) ms total")

        try? await Task.sleep(nanoseconds: 5_000_000_000)
        let cpuUsed = cpuSeconds() - cpuBefore

        let firstFrames = recorders.compactMap(\.arrivals.first).sorted()
        let totalFrames = recorders.reduce(0) { $0 + $1.arrivals.count }
        let distinctFrames = recorders.reduce(0) { $0 + $1.distinct }
        if let median = firstFrames.isEmpty ? nil : firstFrames[firstFrames.count / 2] {
            print(String(format: "   first frame: median %.1f ms, min %.1f, max %.1f",
                         median, firstFrames.first ?? 0, firstFrames.last ?? 0))
        }
        print("   over 5 s: \(totalFrames) frames delivered, \(distinctFrames) with changed content")
        print(String(format: "   → %.1f frames/s/item delivered, %.1f/s actually different",
                     Double(totalFrames) / 5 / Double(max(streams.count, 1)),
                     Double(distinctFrames) / 5 / Double(max(streams.count, 1))))
        print(String(format: "   CPU while streaming: %.1f%% of one core", cpuUsed / 5 * 100))
        print("   → " + (distinctFrames * 3 < totalFrames
                         ? "delivers on a clock, not on change: a poll. Cost must be justified."
                         : "delivers roughly on change: an event source."))

        for s in streams { try? await s.stopCapture() }

        let cpuIdleBefore = cpuSeconds()
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        print(String(format: "   CPU after stopCapture: %.2f%% of one core (must be ~0)",
                     (cpuSeconds() - cpuIdleBefore) / 2 * 100))

        // ---- B. Cover fidelity, judged by eye ----
        print("\nB. Cover variants over the item strip — watch the menu bar")
        print("   strip x=\(Int(strip.minX)) w=\(Int(strip.width)), 6 s each\n")
        for style in CoverStyle.allCases {
            showCover(style, over: strip)
            print("   showing: \(style.rawValue)")
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            cover?.orderOut(nil)
            cover = nil
            try? await Task.sleep(nanoseconds: 700_000_000)
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
