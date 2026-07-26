import Settings
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var settings: SettingsStore
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Toggle("Launch Bouncer at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { LaunchAtLogin.isEnabled = launchAtLogin }

            Toggle("Show Bouncer in the menu bar", isOn: $settings.preferences.showBouncerIcon)
            Toggle("Reveal when the pointer enters the menu bar", isOn: $settings.preferences.revealOnHover)
            Toggle("Enable an always-hidden section", isOn: $settings.preferences.enableAlwaysHiddenSection)

            Picker("Hide again", selection: rehideMode) {
                ForEach(RehideMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }

            if case .afterDelay(let seconds) = settings.preferences.autoRehide {
                Stepper(
                    "After \(Int(seconds)) seconds",
                    value: delaySeconds,
                    in: 1...120,
                    step: 1
                )
            }
        }
        .formStyle(.grouped)
    }

    private enum RehideMode: CaseIterable, Hashable {
        case never, afterDelay, onFocusedAppChange

        var label: String {
            switch self {
            case .never: "Never"
            case .afterDelay: "After a delay"
            case .onFocusedAppChange: "When switching apps"
            }
        }
    }

    private var rehideMode: Binding<RehideMode> {
        Binding {
            switch settings.preferences.autoRehide {
            case .never: .never
            case .afterDelay: .afterDelay
            case .onFocusedAppChange: .onFocusedAppChange
            }
        } set: { mode in
            settings.preferences.autoRehide = switch mode {
            case .never: .never
            case .afterDelay: .afterDelay(seconds: 10)
            case .onFocusedAppChange: .onFocusedAppChange
            }
        }
    }

    private var delaySeconds: Binding<Double> {
        Binding {
            guard case .afterDelay(let seconds) = settings.preferences.autoRehide else { return 10 }
            return seconds
        } set: { settings.preferences.autoRehide = .afterDelay(seconds: $0) }
    }
}
