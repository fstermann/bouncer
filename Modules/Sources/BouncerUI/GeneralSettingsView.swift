import AppKit
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

            Toggle("Show hidden items in a bar of their own", isOn: $settings.preferences.showItemsInBar)
            if settings.preferences.showItemsInBar {
                Text("Clicking Bouncer's icon opens the bar instead of revealing the menu bar. "
                     + "Needs Screen Recording to read the items, and Accessibility to click them.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Toggle("Slide the bar in and out", isOn: $settings.preferences.animateBar)
                if settings.preferences.animateBar {
                    Slider(value: animationMilliseconds, in: 60...500, step: 20) {
                        Text("Speed")
                    } minimumValueLabel: {
                        Text("Fast")
                    } maximumValueLabel: {
                        Text("Slow")
                    }
                }

                Picker("Bar style", selection: barStyleChoice) {
                    Text("Match the menu bar").tag(BarStyleChoice.automatic)
                    if #available(macOS 26.0, *) {
                        Text("Liquid Glass").tag(BarStyleChoice.glass)
                    }
                    Text("Custom colour").tag(BarStyleChoice.custom)
                }
                if case .custom = settings.preferences.barStyle {
                    // No opacity: the bar covers the real icons, and any alpha shows them.
                    ColorPicker("Colour", selection: barColour, supportsOpacity: false)
                }
            }

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

    private enum BarStyleChoice: Hashable {
        case automatic, glass, custom
    }

    private var barStyleChoice: Binding<BarStyleChoice> {
        Binding {
            switch settings.preferences.barStyle {
            case .automatic: .automatic
            case .glass: .glass
            case .custom: .custom
            }
        } set: { choice in
            settings.preferences.barStyle = switch choice {
            case .automatic: .automatic
            case .glass: .glass
            case .custom: .custom(red: 0.5, green: 0.5, blue: 0.5)
            }
        }
    }

    private var barColour: Binding<Color> {
        Binding {
            guard case .custom(let red, let green, let blue) = settings.preferences.barStyle else {
                return Color(white: 0.5)
            }
            return Color(.sRGB, red: red, green: green, blue: blue)
        } set: { colour in
            guard let resolved = NSColor(colour).usingColorSpace(.sRGB) else { return }
            settings.preferences.barStyle = .custom(
                red: resolved.redComponent,
                green: resolved.greenComponent,
                blue: resolved.blueComponent
            )
        }
    }

    private var animationMilliseconds: Binding<Double> {
        Binding {
            settings.preferences.barAnimationDuration * 1000
        } set: { settings.preferences.barAnimationDuration = $0 / 1000 }
    }

    private var delaySeconds: Binding<Double> {
        Binding {
            guard case .afterDelay(let seconds) = settings.preferences.autoRehide else { return 10 }
            return seconds
        } set: { settings.preferences.autoRehide = .afterDelay(seconds: $0) }
    }
}
