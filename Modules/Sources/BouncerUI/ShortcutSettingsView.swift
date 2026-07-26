import Settings
import SwiftUI

struct ShortcutSettingsView: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            LabeledContent("Reveal hidden items") {
                HotkeyRecorder(combo: $settings.preferences.revealHotkey)
            }
            LabeledContent("Reveal always-hidden items") {
                HotkeyRecorder(combo: $settings.preferences.revealAlwaysHiddenHotkey)
            }
            .disabled(!settings.preferences.enableAlwaysHiddenSection)
        }
        .formStyle(.grouped)
    }
}
