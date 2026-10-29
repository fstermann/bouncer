import CoreGraphics
import Testing

@testable import StandaloneBar

@Suite struct CapturedImageTests {
    /// A clear image with one square painted at `alpha`, the way an icon sits on a status item.
    private func icon(alpha: CGFloat) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: alpha))
        context.fill(CGRect(x: 10, y: 5, width: 10, height: 10))
        return try #require(context.makeImage())
    }

    @Test func anIconDrawnInFullIsFullyDrawn() throws {
        #expect(CapturedImage.isFullyDrawn(try icon(alpha: 1)))
    }

    @Test func anIconPartwayThroughAFadeIsNot() throws {
        #expect(!CapturedImage.isFullyDrawn(try icon(alpha: 0.57)))
    }

    @Test func aBarThatHasNotStartedFadingInIsNot() throws {
        #expect(!CapturedImage.isFullyDrawn(try icon(alpha: 0)))
    }

    @Test func iconsOnNothingHaveAClearCorner() throws {
        #expect(CapturedImage.hasClearCorner(try icon(alpha: 1)))
    }

    @Test func anOpaqueLayerDoesNot() throws {
        let context = try #require(CGContext(
            data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        #expect(!CapturedImage.hasClearCorner(try #require(context.makeImage())))
    }

    @Test func onlyTheTopLeftCornerCounts() throws {
        let context = try #require(CGContext(
            data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        // Core Graphics puts y = 0 at the bottom, so the top-left pixel is at the top row.
        context.fill(CGRect(x: 0, y: 19, width: 1, height: 1))
        #expect(!CapturedImage.hasClearCorner(try #require(context.makeImage())))
    }
}
