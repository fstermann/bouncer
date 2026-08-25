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
