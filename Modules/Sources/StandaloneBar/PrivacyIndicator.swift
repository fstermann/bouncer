import CoreGraphics

/// macOS's camera, microphone and screen recording indicator, which joins the section as it is
/// revealed.
///
/// macOS keeps it on screen whatever the divider does: while the section is hidden it sits right
/// of the divider, and revealing the section moves it in among the section's items. Worked out
/// without it, the section lands one indicator wider than its landing, and the check that the
/// centring held throws the centring away, jumping the whole bar sideways. So where it went is
/// remembered, as the item it followed, and from the next open it is counted as part of the section.
///
/// Told by its window name, which costs Screen Recording; the standalone bar already holds it.
@MainActor
final class PrivacyIndicator {
    /// The section item the indicator followed when it was last there to see. Until then, Wi-Fi,
    /// which is where it was measured landing.
    private var follows: UInt32?
    /// The indicator, when this open counted it in.
    private var joined: UInt32?

    /// What a hidden section is made of: the items parked off the display, plus the indicator
    /// where it is going to land among them, and the run of items it lands left of.
    struct Section {
        let items: [MenuBarItem]
        let order: [UInt32]
        let run: [MenuBarItem]
    }

    /// The section hidden among `all`, packed `like` the order it had last time.
    func section(of all: [MenuBarItem], screens: [CGRect], like order: [UInt32]) -> Section {
        let parked = MenuBarItemGeometry.offScreen(all, screens: screens)
        joined = nil
        guard let follows = follows ?? StatusItemScanner.windowID(named: "WiFi"), let indicator = Self.find(in: all),
              let joining = MenuBarItemGeometry.joining(indicator, after: follows, to: parked, like: order)
        else { return Section(items: parked, order: order, run: all) }
        joined = indicator.windowID
        return Section(items: joining.items, order: joining.order, run: all.filter { $0 != indicator })
    }

    /// Notes where the indicator landed in the revealed `section`, if it is in the bar, and hands
    /// the section back. Without one nothing is learned, so the slot outlives the indicator.
    func learning(from section: [MenuBarItem]) -> [MenuBarItem] {
        if let indicator = Self.find(in: StatusItemScanner.scan()) {
            follows = MenuBarItemGeometry.predecessor(of: indicator, in: section)
        }
        return section
    }

    /// The window IDs of `items` that the divider takes off the display: all but the indicator.
    func parkable(_ items: [MenuBarItem]) -> Set<UInt32> {
        Set(items.map(\.windowID).filter { $0 != joined })
    }

    private static func find(in items: [MenuBarItem]) -> MenuBarItem? {
        guard let id = StatusItemScanner.windowID(named: "AudioVideoModule") else { return nil }
        return items.first { $0.windowID == id && $0.frame.minX >= 0 }
    }
}
