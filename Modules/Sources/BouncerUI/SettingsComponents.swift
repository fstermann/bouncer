import AppKit
import Settings
import StandaloneBar
import SwiftUI

/// A pane in the settings sidebar. The order here is the order they appear.
enum Pane: String, CaseIterable, Identifiable, Hashable {
    case general, revealing, standaloneBar, updates

    var id: Self { self }

    var label: String {
        switch self {
        case .general: "General"
        case .revealing: "Revealing"
        case .standaloneBar: "Standalone bar"
        case .updates: "Updates"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .revealing: "eye"
        case .standaloneBar: "menubar.rectangle"
        case .updates: "arrow.down.circle"
        }
    }
}

/// One selectable row in the settings sidebar: a filled pill when it is the current pane.
struct SidebarRow: View {
    let pane: Pane
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            Label(pane.label, systemImage: pane.symbol)
                .labelStyle(.titleAndIcon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 6).fill(Color.accentColor)
            }
        }
    }
}

/// A colour offered as a swatch, kept in the same sRGB components the preference stores so
/// selection is an exact comparison rather than a round-trip through `Color`.
struct Swatch: Hashable {
    let red: Double
    let green: Double
    let blue: Double

    var colour: Color { Color(.sRGB, red: red, green: green, blue: blue) }
    var style: BarStyle { .custom(red: red, green: green, blue: blue) }

    func matches(_ style: BarStyle) -> Bool { style == self.style }
}

let swatches: [Swatch] = [
    Swatch(red: 0.11, green: 0.11, blue: 0.12),
    Swatch(red: 0.35, green: 0.35, blue: 0.37),
    Swatch(red: 0.78, green: 0.78, blue: 0.80),
    Swatch(red: 0.78, green: 0.24, blue: 0.24),
    Swatch(red: 0.86, green: 0.53, blue: 0.18),
    Swatch(red: 0.25, green: 0.56, blue: 0.31),
    Swatch(red: 0.20, green: 0.45, blue: 0.78),
    Swatch(red: 0.45, green: 0.32, blue: 0.68)
]

struct SwatchShape: View {
    let colour: Color

    var body: some View {
        Circle()
            .fill(colour)
            .frame(width: 16, height: 16)
            .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
    }
}

struct SwatchButton: View {
    let colour: Color
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            SwatchShape(colour: colour)
                .padding(2)
                .overlay {
                    Circle().strokeBorder(.tint, lineWidth: isSelected ? 2 : 0)
                }
        }
        .buttonStyle(.plain)
    }
}

/// A live replica of the standalone bar. Dragging changes its preview immediately; the model
/// then performs the equivalent move on the real menu bar and replaces the preview with truth.
struct StandaloneItemsSection: View {
    @Bindable var arrangement: StandaloneItemArrangement
    let canArrange: Bool
    let style: BarStyle
    @Environment(\.colorScheme) private var colorScheme
    @State private var draggedItem: UInt32?

    var body: some View {
        Section("Items") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Drag to arrange the items in the standalone bar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if !canArrange {
                    Text("Grant both permissions below to load and move items.")
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(.secondary)
                } else if arrangement.items.isEmpty {
                    Text("No standalone items found.")
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 0) {
                            ForEach(arrangement.items, id: \.windowID) { item in
                                replica(for: item)
                                    .onDrag { beginDragging(item) }
                                    .onDrop(
                                        of: [.text],
                                        delegate: StandaloneItemDropDelegate(
                                            destination: item.windowID,
                                            draggedItem: $draggedItem,
                                            arrangement: arrangement
                                        )
                                    )
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(minWidth: 0, minHeight: 48, alignment: .trailing)
                        .animation(.smooth(duration: 0.2), value: arrangement.items.map(\.windowID))
                    }
                    .background(barBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(.separator, lineWidth: 0.5)
                    }
                    .opacity(arrangement.isApplying ? 0.65 : 1)
                }
            }
            .onAppear { if canArrange { arrangement.refresh() } }
            .onChange(of: canArrange) { if canArrange { arrangement.refresh() } }
        }
    }

    private func replica(for item: MenuBarItem) -> some View {
        Group {
            if let image = arrangement.images[item.windowID] {
                Image(decorative: image, scale: backingScale, orientation: .up)
                    .resizable()
                    .frame(width: item.frame.width, height: item.frame.height)
            } else {
                Image(systemName: "questionmark")
                    .frame(width: item.frame.width, height: item.frame.height)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .opacity(draggedItem == item.windowID ? 0.25 : 1)
    }

    @ViewBuilder private var barBackground: some View {
        switch style {
        case .glass:
            Rectangle().fill(.ultraThinMaterial)
        case .automatic:
            Color(white: colorScheme == .dark ? BarStyle.automaticDark : BarStyle.automaticLight)
        case .custom(let red, let green, let blue):
            Color(.sRGB, red: red, green: green, blue: blue)
        }
    }

    private var backingScale: CGFloat { NSScreen.main?.backingScaleFactor ?? 2 }

    private func beginDragging(_ item: MenuBarItem) -> NSItemProvider {
        guard !arrangement.isApplying else { return NSItemProvider() }
        draggedItem = item.windowID
        arrangement.beginPreview()
        return NSItemProvider(object: String(item.windowID) as NSString)
    }
}

private struct StandaloneItemDropDelegate: DropDelegate {
    let destination: UInt32
    @Binding var draggedItem: UInt32?
    let arrangement: StandaloneItemArrangement

    func dropEntered(info: DropInfo) {
        guard let draggedItem else { return }
        withAnimation(.smooth(duration: 0.2)) {
            arrangement.previewMove(draggedItem, over: destination)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let draggedItem else { return false }
        arrangement.commitPreview(of: draggedItem)
        self.draggedItem = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
}

/// One permission's live status, with a shortcut to its System Settings pane while it is
/// missing — the native prompt only re-shows the first time, so a denied permission is
/// fixed there.
struct PermissionRow: View {
    let name: String
    let status: PermissionStatus
    let pane: String
    var note: String?

    var body: some View {
        LabeledContent(name) {
            switch status {
            case .granted:
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.green)
            case .missing:
                HStack(spacing: 8) {
                    Label("Not granted", systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.orange)
                    Button("Open System Settings", action: openPane)
                }
            }
        }
        if status == .missing, let note {
            Text(note)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func openPane() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
