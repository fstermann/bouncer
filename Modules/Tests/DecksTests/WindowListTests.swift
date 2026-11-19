import AppKit
import os
import Testing

@testable import Decks

@Suite struct WindowListTests {
    private func entry(
        id: Int, pid: Int = 100, layer: Int = 0, alpha: Double = 1, name: String? = "Doc",
        frame: CGRect = CGRect(x: 0, y: 0, width: 800, height: 600)
    ) -> [String: Any] {
        var entry: [String: Any] = [
            kCGWindowNumber as String: id,
            kCGWindowOwnerPID as String: pid,
            kCGWindowLayer as String: layer,
            kCGWindowAlpha as String: alpha,
            kCGWindowOwnerName as String: "App",
            kCGWindowBounds as String: frame.dictionaryRepresentation
        ]
        if let name { entry[kCGWindowName as String] = name }
        return entry
    }

    private func windows(_ entries: [[String: Any]], own: pid_t = 1) -> [WindowInfo] {
        WindowList.windows(in: entries, excluding: own) { _ in "com.example.app" }
    }

    @Test func keepsOrdinaryWindowsInOrder() {
        let found = windows([entry(id: 2), entry(id: 1)])
        #expect(found.map(\.id) == [2, 1])
        #expect(found.first?.bundleID == "com.example.app")
        #expect(found.first?.frame == CGRect(x: 0, y: 0, width: 800, height: 600))
    }

    @Test func dropsOtherLayersHiddenAndTinyWindows() {
        let found = windows([
            entry(id: 1, layer: 25),
            entry(id: 2, alpha: 0),
            entry(id: 3, frame: CGRect(x: 0, y: 0, width: 1512, height: 32)),
            entry(id: 4)
        ])
        #expect(found.map(\.id) == [4])
    }

    @Test func dropsBouncersOwnWindows() {
        #expect(windows([entry(id: 1, pid: 7), entry(id: 2)], own: 7).map(\.id) == [2])
    }

    @Test func labelFallsBackToTheAppName() {
        let found = windows([entry(id: 1, name: nil), entry(id: 2, name: ""), entry(id: 3)])
        #expect(found.map(\.label) == ["App", "App", "Doc"])
    }
}

@Suite struct ThumbnailSizeTests {
    @Test func scalesTheLongerSideDownToFit() {
        let size = Thumbnails.captureSize(of: CGSize(width: 1600, height: 1000), longest: 400, scale: 2)
        #expect(size == CGSize(width: 800, height: 500))
    }

    @Test func neverScalesUp() {
        let size = Thumbnails.captureSize(of: CGSize(width: 300, height: 200), longest: 400, scale: 2)
        #expect(size == CGSize(width: 600, height: 400))
    }

    @Test func anEmptyWindowHasNoPicture() {
        #expect(Thumbnails.captureSize(of: .zero, longest: 400, scale: 2) == .zero)
    }
}

@Suite @MainActor struct ThumbnailCacheTests {
    private func window(_ id: CGWindowID, pid: pid_t = 100, title: String = "Document") -> WindowInfo {
        WindowInfo(id: id, pid: pid, bundleID: nil, appName: "Editor", title: title, frame: .zero)
    }

    @Test func reusesPictureAfterTitleChanges() {
        let picture = NSImage(size: CGSize(width: 2, height: 2))
        let cache = ThumbnailCache(windows: [window(1)], pictures: [1: picture])
        let pictures = cache.pictures(for: [window(1, title: "Renamed")])
        #expect(pictures[1] === picture)
    }

    @Test func skipsClosedNewAndUncapturedWindowsAndReusedNumbers() {
        let picture = NSImage(size: CGSize(width: 2, height: 2))
        let cache = ThumbnailCache(windows: [window(1), window(2), window(3)], pictures: [1: picture, 2: picture])
        let pictures = cache.pictures(for: [window(2, pid: 200), window(3), window(4)])
        #expect(pictures.isEmpty)
    }
}

@Suite @MainActor struct ThumbnailCaptureTests {
    private func makeImage() throws -> CGImage {
        try #require(CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )?.makeImage())
    }

    @Test func deliversEveryWindowWithAtMostEightCapturesOutstanding() async throws {
        let image = try makeImage()
        let windows: [CGWindowID] = Array(1...24)
        let outstanding = OSAllocatedUnfairLock(initialState: 0)
        var delivered: [CGWindowID] = []
        await Thumbnails.capture(windows, scale: 1, imageOf: { _ in
            let count = outstanding.withLock { count in
                count += 1
                return count
            }
            #expect(count <= 8)
            return image
        }, deliver: { id, _ in
            outstanding.withLock { $0 -= 1 }
            delivered.append(id)
        })
        #expect(delivered.sorted() == windows)
    }

    @Test func closingDuringDeliverySkipsRemainingWindows() async throws {
        let image = try makeImage()
        var capture: Task<Void, Never>?
        var delivered: [CGWindowID] = []
        capture = Task {
            await Thumbnails.capture(Array(1...24), scale: 1, imageOf: { id in
                #expect(id <= 8)
                return image
            }, deliver: { id, _ in
                delivered.append(id)
                capture?.cancel()
            })
        }
        await capture?.value
        #expect(delivered.count == 1)
    }
}
