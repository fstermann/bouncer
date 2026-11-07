import AppKit
import MenuBar
import SwiftUI

/// The reminders as a black tab grown out of the notch's right side, the presentation timer's mirror,
/// only as wide as what it says, so it covers as few items as it can.
/// The soonest shows, with how many more wait behind it; a click opens its page, the cross dismisses it.
final class ReminderTabWindow: NSPanel {
    private static let maxWidth: CGFloat = 260
    private let screenFrame: CGRect
    private let notch: (range: ClosedRange<CGFloat>, isReal: Bool)
    private let height: CGFloat
    private let hosting: NSHostingView<ReminderTab?>
    private weak var reminders: ReminderController?

    init(reminders: ReminderController, on screen: NSScreen) {
        self.reminders = reminders
        screenFrame = screen.frame
        notch = DisplayNotch.range(
            left: screen.auxiliaryTopLeftArea, right: screen.auxiliaryTopRightArea, screen: screen.frame
        )
        height = screen.menuBarHeight
        hosting = NSHostingView(rootView: nil)
        hosting.sizingOptions = []
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // Under the pages' panel, which covers it while open, as it does the timer.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 3)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        contentView = hosting
    }

    /// Shows `reminder`, with `more` waiting behind it. Into the notch a little, so the tab reads as
    /// part of it, its square end hidden behind it. Without a notch, a pill just under the menu bar at
    /// the top centre, where it covers no item.
    func show(_ reminder: Reminder, more: Int) {
        let tab = ReminderTab(
            reminder: reminder, more: more, isBesideNotch: notch.isReal,
            open: { [weak reminders] in reminders?.open(reminder) },
            dismiss: { [weak reminders] in reminders?.dismiss(reminder) }
        )
        hosting.rootView = tab
        // Measured on its own: a hosting view kept from sizing its window reports no fitting size.
        let natural = NSHostingController(rootView: tab.fixedSize())
            .sizeThatFits(in: CGSize(width: Self.maxWidth, height: height))
        let width = min(Self.maxWidth, natural.width).rounded(.up)
        let left = notch.isReal ? notch.range.upperBound - 8 : (screenFrame.midX - width / 2).rounded()
        let bottom = screenFrame.maxY - height * (notch.isReal ? 1 : 2)
        setFrame(CGRect(x: left, y: bottom, width: width, height: height), display: true)
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

struct ReminderTab: View {
    let reminder: Reminder
    let more: Int
    let isBesideNotch: Bool
    let open: @MainActor () -> Void
    let dismiss: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: open) {
                HStack(spacing: 5) {
                    icon(reminder.kind)
                    Text(reminder.title).lineLimit(1).truncationMode(.tail)
                    Text(reminder.detail).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                    if more > 0 { Text("+\(more)").foregroundStyle(.secondary).fixedSize() }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(help)
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.white)
        .padding(.leading, isBesideNotch ? 14 : 10)
        .padding(.trailing, 10)
        .frame(maxHeight: .infinity)
        .background(
            UnevenRoundedRectangle(
                bottomLeadingRadius: isBesideNotch ? 0 : 8, bottomTrailingRadius: 8,
                topTrailingRadius: isBesideNotch ? 0 : 8
            ).fill(.black)
        )
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private func icon(_ kind: Reminder.Kind) -> some View {
        switch kind {
        case .todo: Image(systemName: "bell.fill").foregroundStyle(.orange)
        case .meeting: Image(systemName: "person.2.fill").foregroundStyle(.blue)
        case .claude: Image(nsImage: ClaudeMark.image(side: 12)).renderingMode(.template).foregroundStyle(.orange)
        }
    }

    private var help: String {
        switch reminder.kind {
        case .todo: "Open the todos"
        case .meeting: "Open the meeting's note"
        case .claude: "Open the chat"
        }
    }
}
