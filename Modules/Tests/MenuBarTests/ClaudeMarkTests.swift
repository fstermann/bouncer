import CoreGraphics
import Testing

@testable import MenuBar

@Suite struct ClaudeMarkTests {
    @Test func theMarkFillsItsBox() {
        let box = ClaudeMark.path.boundingBoxOfPath
        #expect(abs(box.minX) < 0.1 && abs(box.minY) < 0.1)
        #expect(abs(box.maxX - 24) < 0.1 && abs(box.maxY - 24) < 0.1)
    }

    @Test func numbersRunTogetherSplitAtSignsAndSecondPoints() {
        let path = SVGPath.parse("M1 1l.5.5-.25-.25h2v-1Z")
        #expect(path.currentPoint == CGPoint(x: 1, y: 1))
        #expect(path.boundingBoxOfPath == CGRect(x: 1, y: 0.25, width: 2.25, height: 1.25))
    }
}
