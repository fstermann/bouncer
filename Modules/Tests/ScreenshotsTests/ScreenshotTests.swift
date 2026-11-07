import CoreGraphics
import Testing

@testable import Screenshots

@Suite struct ScreenshotTests {
    @Test func takesTheScreenByItsRectSilently() {
        let rect = CGRect(x: 1512, y: -200, width: 1920, height: 1080)
        #expect(Screenshot.arguments(for: .screen, in: rect, to: "/t/a.png") == [
            "-x", "-R", "1512,-200,1920,1080", "/t/a.png"
        ])
    }

    @Test func letsTheUserPickARegion() {
        #expect(Screenshot.arguments(for: .region, in: nil, to: "/t/a.png") == ["-x", "-i", "/t/a.png"])
    }

    @Test func measuresFromTheMainDisplaysTopLeft() {
        let above = CGRect(x: 0, y: 982, width: 1920, height: 1080)
        #expect(Screenshot.captureRect(of: above, mainHeight: 982) == CGRect(x: 0, y: -1080, width: 1920, height: 1080))
        let main = CGRect(x: 0, y: 0, width: 1512, height: 982)
        #expect(Screenshot.captureRect(of: main, mainHeight: 982) == main)
    }
}
