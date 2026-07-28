// Spike 1 — what does the window server tell us about status items, without any permission?
//
// Questions:
//   1. Which window layer do status items live on, on macOS 26?
//   2. Do items pushed off screen by an expanded divider still report a valid frame?
//   3. How much can we tell items apart (owner pid, window name) with no Screen Recording?
//
// Build: swiftc -O Spikes/enumerate.swift -o Spikes/.bin/enumerate

import AppKit

struct Win {
    let number: Int
    let layer: Int
    let pid: Int
    let owner: String
    let name: String
    let bounds: CGRect
    let onScreen: Bool
    let alpha: Double
}

func windows() -> [Win] {
    let opts = CGWindowListOption(arrayLiteral: .optionAll, .excludeDesktopElements)
    guard let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
        return []
    }
    return raw.compactMap { d in
        guard let boundsDict = d[kCGWindowBounds as String] as? [String: Any],
              let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
        else { return nil }
        return Win(
            number: d[kCGWindowNumber as String] as? Int ?? -1,
            layer: d[kCGWindowLayer as String] as? Int ?? 0,
            pid: d[kCGWindowOwnerPID as String] as? Int ?? -1,
            owner: d[kCGWindowOwnerName as String] as? String ?? "?",
            name: d[kCGWindowName as String] as? String ?? "",
            bounds: rect,
            onScreen: d[kCGWindowIsOnscreen as String] as? Bool ?? false,
            alpha: d[kCGWindowAlpha as String] as? Double ?? 1
        )
    }
}

let screens = NSScreen.screens.map(\.frame)
print("Screens (AppKit, bottom-left origin): \(screens)")
print("Screen recording preflight: \(CGPreflightScreenCaptureAccess())")
print("")

let all = windows()

// Layer histogram — find where status items actually live before assuming 25.
var byLayer: [Int: Int] = [:]
for w in all { byLayer[w.layer, default: 0] += 1 }
print("Window count by layer: \(byLayer.sorted { $0.key < $1.key })")
print("")

// The menu bar band is the top ~24-40pt of the main display. Status items are the
// windows sitting in it above the normal window layer.
let candidates = all
    .filter { $0.layer >= 20 && $0.layer <= 30 }
    .sorted { ($0.layer, $0.bounds.minX) < ($1.layer, $1.bounds.minX) }

func pad(_ s: String, _ n: Int) -> String {
    let t = String(s.prefix(n))
    return t + String(repeating: " ", count: max(0, n - t.count))
}

print([pad("layer", 6), pad("winId", 7), pad("pid", 7), pad("owner", 22),
       pad("name", 26), pad("bounds (CG, top-left origin)", 34), pad("vis", 4), "alpha"].joined(separator: " "))
for w in candidates {
    let b = w.bounds
    let boundsStr = String(format: "x=%.0f y=%.0f w=%.0f h=%.0f", b.minX, b.minY, b.width, b.height)
    print([pad("\(w.layer)", 6), pad("\(w.number)", 7), pad("\(w.pid)", 7), pad(w.owner, 22),
           pad(w.name, 26), pad(boundsStr, 34), pad(w.onScreen ? "yes" : "NO", 4),
           String(format: "%.2f", w.alpha)].joined(separator: " "))
}

print("")
let offScreen = candidates.filter { w in
    !screens.isEmpty && !screens.contains { $0.intersects(CGRect(x: w.bounds.minX, y: 0, width: max(w.bounds.width, 1), height: 1)) }
}
print("Candidates whose x-range falls outside every screen: \(offScreen.count)")
for w in offScreen {
    print("  layer \(w.layer) pid \(w.pid) \(w.owner) x=\(Int(w.bounds.minX)) w=\(Int(w.bounds.width)) onScreen=\(w.onScreen)")
}
