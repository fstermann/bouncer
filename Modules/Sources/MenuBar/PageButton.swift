import AppKit
import Settings

/// The notch panel's page showing, as one icon just right of the notch, which lists every page that
/// is on when clicked. Every page draws it in the same place, so it stays put while the pages change
/// around it, and it is as wide for two pages as for ten.
@MainActor
public final class PageButton: NSView {
    /// The pages that are on. Fewer than two hides the button.
    public var pages: [NotchPage] = [] { didSet { isHidden = pages.count < 2 } }
    /// The page this button is drawn on.
    public var current: NotchPage? { didSet { icon.image = current.flatMap(Self.image) } }
    /// Picking one of the other pages.
    public var onPick: (@MainActor (NotchPage) -> Void)?

    private let icon = NSImageView()

    public static let size: CGFloat = 20
    /// From the notch's right edge, so the button reads as beside the notch rather than in it.
    public static let gap: CGFloat = 6

    public init() {
        super.init(frame: CGRect(x: 0, y: 0, width: Self.size, height: Self.size))
        isHidden = true
        wantsLayer = true
        layer?.cornerRadius = Self.size / 2
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
        icon.frame = bounds
        icon.symbolConfiguration = .init(pointSize: 11, weight: .regular)
        icon.contentTintColor = .white.withAlphaComponent(0.9)
        addSubview(icon)
        toolTip = "Switch page"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Puts the button's left edge at `origin`, centred on `midY`.
    public func place(atX origin: CGFloat, midY: CGFloat) {
        frame = CGRect(x: origin, y: (midY - Self.size / 2).rounded(), width: Self.size, height: Self.size)
    }

    override public func mouseDown(with event: NSEvent) { showPages() }

    /// Lists the pages under the button, the one showing ticked.
    public func showPages() {
        guard !isHidden else { return }
        let menu = NSMenu()
        for (index, page) in pages.enumerated() {
            let item = NSMenuItem(title: page.help, action: #selector(picked), keyEquivalent: page.key ?? "")
            item.keyEquivalentModifierMask = [.command, .shift]
            item.target = self
            item.tag = index
            item.image = Self.image(for: page)
            item.state = page == current ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: CGPoint(x: 0, y: -4), in: self)
    }

    @objc private func picked(_ item: NSMenuItem) {
        guard pages.indices.contains(item.tag), pages[item.tag] != current else { return }
        onPick?(pages[item.tag])
    }

    private static func image(for page: NotchPage) -> NSImage? {
        NSImage(systemSymbolName: page.symbol, accessibilityDescription: page.help)
    }
}

extension NotchPage {
    public var symbol: String {
        switch self {
        case .items: "menubar.rectangle"
        case .todos: "checklist"
        case .notes: "note.text"
        case .claude: "sparkle"
        }
    }

    public var help: String {
        switch self {
        case .items: "Hidden items"
        case .todos: "Todos"
        case .notes: "Meeting notes"
        case .claude: "Ask Claude"
        }
    }

    /// The letter of its ⌘⇧ shortcut, shown in the list.
    var key: String? {
        switch self {
        case .items: nil
        case .todos: "b"
        case .notes: "n"
        case .claude: "c"
        }
    }
}
