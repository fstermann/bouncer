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
}
