import CoreGraphics
import Testing

@testable import StandaloneBar

@Suite("Captured item pixels")
@MainActor
struct ItemCaptureTests {
    @Test("A correctly sized transparent capture is not an item image")
    func rejectsTransparentCapture() throws {
        let transparent = try image(alpha: 0)

        #expect(!ItemCapture.containsVisiblePixels(transparent))
    }

    @Test("Any drawn alpha makes a capture usable")
    func acceptsDrawnCapture() throws {
        let opaque = try image(alpha: 255)

        #expect(ItemCapture.containsVisiblePixels(opaque))
    }

    @Test("One hardware image is cropped into every requested item")
    func cropsHardwareComposite() throws {
        let composite = try solidImage(width: 4, height: 2)
        let items = [
            MenuBarItem(windowID: 1, frame: CGRect(x: 10, y: 0, width: 2, height: 2)),
            MenuBarItem(windowID: 2, frame: CGRect(x: 12, y: 0, width: 2, height: 2))
        ]

        let result = ItemCapture.croppedImages(from: composite, for: items)

        #expect(result?.keys.sorted() == [1, 2])
    }

    private func image(alpha: UInt8) throws -> CGImage {
        var pixel: [UInt8] = [255, 255, 255, alpha]
        let context = try #require(
            CGContext(
                data: &pixel,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        return try #require(context.makeImage())
    }

    private func solidImage(width: Int, height: Int) throws -> CGImage {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let context = try #require(
            CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        return try #require(context.makeImage())
    }
}
