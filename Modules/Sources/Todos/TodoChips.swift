import AppKit
import SwiftUI

/// The colours a tag's chip can be drawn in, stored by name.
enum TagColor: String, CaseIterable {
    case grey, red, orange, yellow, green, blue, purple, pink

    var color: Color? {
        switch self {
        case .grey: nil
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        }
    }
}

/// The colours `tag` can be drawn in, as swatches rather than a system menu: a system menu shows the
/// names in plain text, and the pointer reaching into it reads as leaving the panel.
struct Palette: View {
    let page: TodoPage
    let tag: String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(TagColor.allCases, id: \.self) { color in
                let isCurrent = (page.tagColors[tag] ?? TagColor.grey.rawValue) == color.rawValue
                Button {
                    page.setColor(color, of: tag)
                    page.menu = nil
                } label: {
                    Circle()
                        .fill(color.color ?? .white.opacity(0.3))
                        .frame(width: 10, height: 10)
                        .padding(3)
                        .overlay(Circle().stroke(.white, lineWidth: isCurrent ? 1 : 0))
                }
                .buttonStyle(.plain)
                .help(color.rawValue.capitalized)
            }
            if !page.categories(under: tag).isEmpty {
                Button {
                    page.menu = nil
                    page.categories(under: tag).forEach { page.onRemoveCategory?($0) }
                } label: {
                    Image(systemName: "trash").font(.caption).foregroundStyle(.secondary).padding(.leading, 6)
                }
                .buttonStyle(.plain)
                .help("Delete tag")
            }
        }
    }
}

/// Catches a right-click on what it lies over, and lets every other click through to it.
struct RightClick: NSViewRepresentable {
    let action: @MainActor () -> Void

    func makeNSView(context: Context) -> RightClickView {
        RightClickView()
    }

    func updateNSView(_ view: RightClickView, context: Context) {
        view.action = action
    }
}

final class RightClickView: NSView {
    var action: (@MainActor () -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        NSApp.currentEvent?.type == .rightMouseDown ? super.hitTest(point) : nil
    }

    override func rightMouseDown(with event: NSEvent) {
        action?()
    }
}

struct Chip: View {
    let text: String
    /// The tag a nested tag's chip sits under, shown dimmed before it.
    var parent: String?
    var color: Color?
    var isSelected = false
    var count: Int?

    var body: some View {
        HStack(spacing: 4) {
            Text(parent.map { "\($0) " } ?? "").font(.system(size: 8.5)).foregroundStyle(foreground.opacity(0.55))
                + Text(text)
            if let count { Text("\(count)").opacity(0.55) }
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(foreground)
        .background(Capsule().fill(fill))
    }

    /// Selected chips are filled solid; the rest are tinted, so a coloured tag never reads as chosen.
    private var foreground: Color {
        if isSelected { return color == nil || color == .yellow ? .black : .white }
        return color ?? .white
    }

    private var fill: Color {
        if isSelected { return color ?? .white }
        return (color ?? .white).opacity(color == nil ? 0.15 : 0.2)
    }
}

extension Chip {
    /// A tag's chip: a nested tag shows its last part, after the tags above it.
    init(tag: String, color: Color? = nil, isSelected: Bool = false, count: Int? = nil) {
        self.init(
            text: TagPath.leaf(of: tag), parent: TagPath.parent(of: tag), color: color, isSelected: isSelected,
            count: count
        )
    }
}
