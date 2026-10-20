import BouncerFoundation
import CoreGraphics
import MenuBar
import Settings

/// Centres the hidden section under the notch, so a notch-style panel grows evenly either side
/// of it.
///
/// The section is pushed left by widening the divider on its right, which macOS does not always
/// take quietly: measured, it reorders the items around a widened item whenever one would sit
/// across the notch's edge. So the landing is checked, and the shift dropped when it went wrong.
@MainActor
struct NotchCentring {
    let menuBar: MenuBarManager

    /// Where `parked` lands when revealed, as `MenuBarItemGeometry.landingStrip` works it out, but
    /// shifted to centre under the notch for the notch style.
    func landing(for parked: [MenuBarItem], leftOf all: [MenuBarItem], as style: BarStyle) -> CGRect {
        let landing = MenuBarItemGeometry.landingStrip(for: parked, leftOf: all)
        let notch = style == .notch ? Notch.on(displayOf: landing) : nil
        let shift = notch.map { MenuBarItemGeometry.shiftCentring(landing, on: $0.centre) } ?? 0
        menuBar.sectionShift = shift
        return landing.offsetBy(dx: -shift, dy: 0)
    }

    /// The revealed section, or, if an item crossed the divider on the way, the section put back
    /// where it lands unshifted. Off centre the panel still grows out of the notch; it reaches
    /// further to one side.
    func confirm(_ revealed: [MenuBarItem], in landing: CGRect, of hidden: Set<UInt32>) async -> [MenuBarItem] {
        guard menuBar.sectionShift > 0,
              !MenuBarItemGeometry.landedIntact(revealed, in: landing, among: onScreen())
        else { return revealed }
        Log.menuBar.info("Standalone bar: an item crossed the divider at the notch — not centring")
        let before = PlacementWait.frames(of: hidden)
        menuBar.sectionShift = 0
        await PlacementWait.stillness(of: hidden, movedFrom: before)
        return onScreen().filter { hidden.contains($0.windowID) }
    }

    private func onScreen() -> [MenuBarItem] {
        MenuBarItemGeometry.excludingDividers(StatusItemScanner.scan()).filter { $0.frame.minX >= 0 }
    }
}
