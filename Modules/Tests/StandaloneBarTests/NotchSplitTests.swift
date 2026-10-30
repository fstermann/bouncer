import CoreGraphics
import Testing

@testable import StandaloneBar

private let notch: ClosedRange<CGFloat> = 663.5...848.5
private let end: CGFloat = 1235

private func item(_ minX: CGFloat, _ maxX: CGFloat, top: CGFloat = 4) -> CGRect {
    CGRect(x: minX, y: top, width: maxX - minX, height: 24)
}

@Suite("Splitting the section around the notch")
struct NotchSplitTests {
    // Real frames from macOS 27.2 with the divider widened by 150 pt: four items overflowed left of
    // the notch, three stayed right of it, Wi-Fi sits past the section's end.
    private let split = [
        item(492, 536), item(534, 572), item(570, 612), item(610, 644),
        item(886, 904), item(910, 950), item(948, 994), item(1001, 1027),
        item(1243, 1265)
    ]

    @Test("The shift leaves room right of the notch for half the section")
    func shiftHalves() {
        // 289 pt of items, measured revealed without a shift; 150 pt was what split them evenly.
        let shift = NotchSplit.shift(for: 289, endingAt: end, notch: notch)
        #expect(abs(shift - 155) < 1)
    }

    @Test("A section wider than the bar right of the notch gets no shift")
    func noRoom() {
        #expect(NotchSplit.shift(for: 1000, endingAt: end, notch: notch) == 0)
    }

    @Test("The width adds both sides' spans and leaves out items past the section")
    func width() {
        let chevron = item(886, 904)
        let width = NotchSplit.hiddenWidth(of: split.filter { $0 != chevron }, notch: notch, end: end)
        #expect(width == CGFloat((644 - 492) + (1027 - 910)))
    }

    @Test("An item macOS had no room for does not count")
    func dropped() {
        let width = NotchSplit.hiddenWidth(of: [item(910, 950), item(0, 40, top: -33)], notch: notch, end: end)
        #expect(width == 40)
    }

    @Test("With nothing revealed there is no width")
    func nothing() {
        #expect(NotchSplit.hiddenWidth(of: [item(1243, 1265)], notch: notch, end: end) == nil)
    }

    @Test("The band reaches past the outermost items on both sides")
    func band() {
        let band = NotchSplit.band(over: split, notch: notch, end: end)
        #expect(band == (492 - NotchSplit.bandPadding)...(1027 + NotchSplit.bandPadding))
    }

    @Test("With nothing revealed the band is the notch")
    func bandOverNothing() {
        #expect(NotchSplit.band(over: [], notch: notch, end: end) == notch)
    }

    @Test("The shade runs from the notch to just past the chevron")
    func shade() {
        let shade = NotchSplit.shade(over: CGRect(x: 886, y: 1, width: 18, height: 30), notch: notch)
        #expect(shade.minX == notch.upperBound)
        #expect(shade.maxX == 904 + NotchSplit.shadePadding)
        #expect(shade.minY == 0)
    }
}
