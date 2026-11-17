import Decks
import Settings
import SwiftUI

/// The window overview: whether it is on, and the permissions it needs.
struct DeckOptions: View {
    @Binding var preferences: Preferences
    @Bindable var permissions: DecksPermissions

    var body: some View {
        Section(DecksController.name, systemImage: "square.stack.3d.up") {
            Toggle(isOn: $preferences.enableDecks) {
                Text("Show a window overview")
                Text("Press \(preferences.decksShortcut.name) to see every window, grouped into decks. "
                     + "Needs Accessibility to bring windows forward, and Screen Recording to show them.")
            }
            .onChange(of: preferences.enableDecks) {
                if preferences.enableDecks { permissions.request() }
            }
            if preferences.enableDecks {
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
