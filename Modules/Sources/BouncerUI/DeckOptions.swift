import AppKit
import BouncerFoundation
import Decks
import Settings
import SwiftUI

/// The window overview: whether it is on, its shortcut, the permissions it needs, and its decks.
struct DeckOptions: View {
    @Binding var preferences: Preferences
    @Bindable var permissions: DecksPermissions

    var body: some View {
        Section(DecksController.name, systemImage: "square.stack.3d.up") {
            Toggle(isOn: $preferences.enableDecks) {
                Text("Show a window overview")
                Text("Press \(preferences.decksShortcut.name) to see every window and Space, grouped into decks. "
                     + "Needs Accessibility to bring windows forward, and Screen Recording to show them.")
            }
            .onChange(of: preferences.enableDecks) {
                if preferences.enableDecks { permissions.request() }
            }
            if preferences.enableDecks {
                LabeledContent("Shortcut") {
                    HStack(spacing: 8) {
                        ShortcutRecorder(shortcut: $preferences.decksShortcut)
                        if preferences.decksShortcut != Preferences.defaultDecksShortcut {
                            Button("Reset") { preferences.decksShortcut = Preferences.defaultDecksShortcut }
                        }
                    }
                }
                if preferences.decksShortcut.name == "F3" {
                    Text("Turn off Mission Control's F3 in System Settings, Keyboard, Keyboard Shortcuts, "
                         + "Mission Control, or macOS takes the key first.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                PermissionRow(
                    name: "Screen Recording",
                    status: permissions.screenRecording ? .granted : .missing,
                    pane: "Privacy_ScreenCapture",
                    note: "Takes effect after Bouncer restarts."
                )
                PermissionRow(
                    name: "Accessibility",
                    status: permissions.accessibility ? .granted : .missing,
                    pane: "Privacy_Accessibility"
                )
                DeckList(decks: $preferences.decks)
            }
        }
    }
}

/// Each deck's colour, name and level, and a button to delete it. Deleting a deck leaves its windows open.
private struct DeckList: View {
    @Binding var decks: [Deck]

    var body: some View {
        if decks.isEmpty {
            LabeledContent("Decks") {
                Text("None yet. Drag a card onto another in the overview.")
                    .foregroundStyle(.secondary)
            }
        } else {
            ForEach($decks) { $deck in
                HStack(spacing: 10) {
                    Menu {
                        ForEach(DeckColor.allCases, id: \.self) { color in
                            Button(color.rawValue.capitalized) { deck.color = color }
                        }
                    } label: {
                        Circle().fill(deck.color.color).frame(width: 12, height: 12)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .fixedSize()
                    TextField("Name", text: $deck.name)
                        .textFieldStyle(.plain)
                    Spacer()
                    Text(deck.kind == .windows ? "Windows" : "Spaces")
                        .foregroundStyle(.secondary)
                    Button(role: .destructive) {
                        decks.removeAll { $0.id == deck.id }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Delete this deck. Its windows stay open.")
                }
            }
        }
    }
}

/// A shortcut field: click it, then press the keys. Escape cancels.
private struct ShortcutRecorder: View {
    @Binding var shortcut: HotKey.Shortcut
    @State private var monitor: Any?

    var body: some View {
        Button(monitor == nil ? shortcut.name : "Type a shortcut…") {
            monitor == nil ? start() : stop()
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(53) {
                stop()
            } else if let recorded = HotKey.Shortcut.recorded(
                keyCode: event.keyCode, flags: event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
            ) {
                shortcut = recorded
                stop()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
