import AppKit

/// Black over the stretch of bar a section can land in, put up before a macOS 27 reveal.
///
/// There the panel cannot be built where the section is about to land, because nothing says which
/// items it holds until they are back in the bar. They can only land between the notch and the
/// divider, though, so that stretch is hidden first, black on the black the panel grows out of.
@MainActor
final class Curtain {
    private var window: BarWindow?

    func show(over rect: CGRect) {
        let curtain = window ?? BarWindow(frame: rect, level: CoverWindow.aboveItems)
        curtain.setFrame(cgFrame: rect)
        curtain.backgroundColor = .black
        curtain.ignoresMouseEvents = true
        curtain.orderFrontRegardless()
        window = curtain
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
    }
}
