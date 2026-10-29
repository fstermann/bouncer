import AppKit
import MenuBar
import Settings
import StandaloneBar
import SwiftUI
import Todos
import UniformTypeIdentifiers

/// A pane in the settings sidebar. The order here is the order they appear.
enum Pane: String, CaseIterable, Identifiable, Hashable {
    case general, revealing, standaloneBar, todos, updates

    var id: Self { self }

    var label: String {
        switch self {
        case .general: "General"
        case .revealing: "Revealing"
        case .standaloneBar: "Standalone bar"
        case .todos: "Todos"
        case .updates: "Updates"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .revealing: "eye"
        case .standaloneBar: "menubar.rectangle"
        case .todos: "checklist"
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

/// Revealing by pointer alone, and how long it waits first: the Dock's own delay, or one of the
/// user's. Custom starts from the Dock's, so switching to it changes nothing until the slider moves.
struct HoverRevealOptions: View {
    @Binding var preferences: Preferences

    var body: some View {
        Toggle("Reveal when the pointer enters the menu bar", isOn: $preferences.revealOnHover)
        Toggle(isOn: $preferences.revealNearNotch) {
            Text("Reveal when the pointer reaches the notch")
            Text("Closes again when the pointer leaves. Without a notch, the top centre of the menu bar.")
        }
        if preferences.revealOnHover || preferences.revealNearNotch {
            delayPicker
        }
    }

    @ViewBuilder private var delayPicker: some View {
        Picker("Delay before revealing", selection: followsDock) {
            Text("Match the Dock (\(Self.label(DockDelay.current)))").tag(true)
            Text("Custom").tag(false)
        }
        if case .seconds(let seconds) = preferences.hoverDelay {
            Slider(value: custom, in: 0...HoverDelay.longest, step: 0.01) {
                Text(Self.label(seconds))
            } minimumValueLabel: {
                Text("0 ms")
            } maximumValueLabel: {
                Text("\(Int(HoverDelay.longest))s")
            }
        }
    }

    private var followsDock: Binding<Bool> {
        Binding { preferences.hoverDelay == .matchDock } set: { matches in
            preferences.hoverDelay = matches ? .matchDock : .seconds(min(DockDelay.current, HoverDelay.longest))
        }
    }

    private var custom: Binding<Double> {
        Binding {
            guard case .seconds(let seconds) = preferences.hoverDelay else { return 0 }
            return seconds
        } set: { preferences.hoverDelay = .seconds($0) }
    }

    private static func label(_ seconds: TimeInterval) -> String {
        "\(Int((seconds * 1000).rounded())) ms"
    }
}

/// The todo file the notch panel's todo page reads and writes.
struct TodoOptions: View {
    @Binding var preferences: Preferences

    var body: some View {
        Section {
            LabeledContent("File") {
                HStack(spacing: 8) {
                    Text(fileName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose…", action: choose)
                    if preferences.todoFile != nil {
                        Button("Use Local") { preferences.todoFile = nil }
                    }
                }
            }
            Text("Bouncer shows the open `- [ ]` lines of this Markdown file under the notch, and adds new "
                 + "ones at its end. Without a chosen file, it keeps them in a local one. Hover near the notch "
                 + "to open it, or use the switch in the bar.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var fileName: String {
        guard let bookmark = preferences.todoFile else { return "Local" }
        return TodoController.url(of: bookmark)?.lastPathComponent ?? "Not found"
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url, let bookmark = TodoController.bookmark(for: url)
        else { return }
        preferences.todoFile = bookmark
    }
}
