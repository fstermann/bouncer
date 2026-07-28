import CoreGraphics
import Testing

@testable import StandaloneBar

/// Shaped like the dictionaries `CGWindowListCopyWindowInfo` returns.
private func window(
    number: Int,
    layer: Int = 25,
    originX: CGFloat,
    width: CGFloat,
    originY: CGFloat = 0,
    height: CGFloat = 33
) -> [String: Any] {
    let bounds = CGRect(x: originX, y: originY, width: width, height: height)
    return [
        kCGWindowNumber as String: number,
        kCGWindowLayer as String: layer,
        kCGWindowBounds as String: bounds.dictionaryRepresentation as Any
    ]
}

@Suite("Status item scanning")
struct StatusItemScannerTests {
    @Test("Keeps status-layer windows in the menu bar band, left to right")
    func keepsStatusItems() {
        // Recorded from a real bar: a hidden section off screen, then visible items.
        let windows = [
            window(number: 3, originX: 1229, width: 67),
            window(number: 1, originX: -4079, width: 40),
            window(number: 2, originX: 1191, width: 38)
        ]
        #expect(StatusItemScanner.items(from: windows).map(\.windowID) == [1, 2, 3])
    }

    @Test("Off-screen items are kept — they are the section the bar exists to show")
    func keepsOffScreenItems() {
        let items = StatusItemScanner.items(from: [window(number: 1, originX: -4079, width: 40)])
        #expect(items.first?.frame.minX == -4079)
    }

    @Test("Windows on other layers are not status items")
    func rejectsOtherLayers() {
        // Layer 24 is the menu bar itself; 26 is where other apps put overlays.
        let windows = [
            window(number: 1, layer: 24, originX: 0, width: 1512),
            window(number: 2, layer: 26, originX: 0, width: 1512),
            window(number: 3, layer: 25, originX: 1191, width: 38)
        ]
        #expect(StatusItemScanner.items(from: windows).map(\.windowID) == [3])
    }

    @Test("A tall window starting at the top of the screen is not a status item")
    func rejectsTallWindows() {
        let windows = [window(number: 1, originX: 100, width: 400, height: 600)]
        #expect(StatusItemScanner.items(from: windows).isEmpty)
    }

    @Test("A window below the menu bar band is not a status item")
    func rejectsLowerWindows() {
        // A popover anchored under the bar sits on the same layer.
        let windows = [window(number: 1, originX: 1258, width: 254, originY: 728, height: 254)]
        #expect(StatusItemScanner.items(from: windows).isEmpty)
    }

    @Test("Malformed entries are skipped rather than crashing the scan")
    func skipsMalformed() {
        let windows: [[String: Any]] = [
            [kCGWindowLayer as String: 25],
            window(number: 1, originX: 1191, width: 38)
        ]
        #expect(StatusItemScanner.items(from: windows).map(\.windowID) == [1])
    }

    @Test("Dividers come back too — filtering them is the caller's decision")
    func keepsDividers() {
        let windows = [window(number: 1, originX: -3825, width: 5016)]
        #expect(StatusItemScanner.items(from: windows).count == 1)
        #expect(MenuBarItemGeometry.excludingDividers(StatusItemScanner.items(from: windows)).isEmpty)
    }
}
