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

/// The colours `tag` can be drawn in, as swatches inside the panel rather than a system menu: a
/// menu shows the names in plain text, and the pointer reaching into it reads as leaving the panel.
struct Palette: View {
    let page: TodoPage
    let tag: String

    var body: some View {
        HStack(spacing: 8) {
            ForEach(TagColor.allCases, id: \.self) { color in
                let isCurrent = (page.tagColors[tag] ?? TagColor.grey.rawValue) == color.rawValue
                Button {
                    page.setColor(color, of: tag)
                    page.coloringTag = nil
                } label: {
                    Circle()
                        .fill(color.color ?? .white.opacity(0.3))
                        .frame(width: 14, height: 14)
                        .padding(3)
                        .overlay(Circle().stroke(.white, lineWidth: isCurrent ? 1.5 : 0))
                }
                .buttonStyle(.plain)
                .help(color.rawValue.capitalized)
            }
            Spacer()
            Button("Done") { page.coloringTag = nil }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
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
    var color: Color?
    var isSelected = false

    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(isSelected && color == nil ? .black : .white)
            .background(Capsule().fill(fill))
    }

    private var fill: Color {
        let base = color ?? .white
        if isSelected { return color ?? .white }
        return base.opacity(color == nil ? 0.15 : 0.4)
    }
}
