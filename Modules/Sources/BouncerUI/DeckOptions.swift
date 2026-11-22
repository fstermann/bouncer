import AppKit
import BouncerFoundation
import Decks
import Settings
import SwiftUI

/// The window overview: whether it is on, its shortcut, and the permissions it needs.
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
                Toggle(isOn: $preferences.decksSwipe) {
                    Text("Swipe up with three fingers to open, down to close")
                    Text("Turn off Mission Control's swipe in Trackpad settings, More Gestures, first, or macOS "
                         + "opens Mission Control as well. Needs Accessibility.")
                }
                if preferences.decksSwipe {
                    LabeledContent("Mission Control swipe") {
                        Button("Open Trackpad Settings") {
                            let pane = "x-apple.systempreferences:com.apple.Trackpad-Settings.extension"
                            if let url = URL(string: pane) { NSWorkspace.shared.open(url) }
                        }
                    }
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
            }
        }
    }
}

/// A shortcut field: click it, then press the keys. Escape alone cancels.
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
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
            if HotKey.Shortcut.cancelsRecording(keyCode: event.keyCode, flags: flags) {
                stop()
            } else if let recorded = HotKey.Shortcut.recorded(keyCode: event.keyCode, flags: flags) {
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
