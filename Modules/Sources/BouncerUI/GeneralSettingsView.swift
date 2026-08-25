import AppKit
import Settings
import StandaloneBar
import SwiftUI
import Updates

struct GeneralSettingsView: View {
    @Bindable var settings: SettingsStore
    let updates: UpdateController
    @Bindable var permissions: StandaloneBarPermissions
    @Environment(\.colorScheme) private var colorScheme
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    // Mirrors of Sparkle's own state, the way `launchAtLogin` mirrors the system. Nothing else
    // writes them, so they are seeded here and re-read only where Sparkle moves them itself.
    @State private var checkForUpdates: Bool
    @State private var installUpdates: Bool

    init(settings: SettingsStore, updates: UpdateController, permissions: StandaloneBarPermissions) {
        _settings = Bindable(settings)
        self.updates = updates
        _permissions = Bindable(permissions)
        _checkForUpdates = State(initialValue: updates.automaticallyChecks)
        _installUpdates = State(initialValue: updates.automaticallyDownloads)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Launch Bouncer at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { LaunchAtLogin.isEnabled = launchAtLogin }

                Toggle("Show Bouncer in the menu bar", isOn: $settings.preferences.showBouncerIcon)
                Toggle("Enable an always-hidden section", isOn: $settings.preferences.enableAlwaysHiddenSection)
            }

            Section("Revealing") {
                Toggle("Reveal when the pointer enters the menu bar", isOn: $settings.preferences.revealOnHover)

                Picker("Hide again", selection: rehideMode) {
                    ForEach(RehideMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                if case .afterDelay(let seconds) = settings.preferences.autoRehide {
                    Slider(value: delaySeconds, in: 1...10, step: 1) {
                        Text("After \(Int(seconds)) seconds")
                    } minimumValueLabel: {
                        Text("1s")
                    } maximumValueLabel: {
                        Text("10s")
                    }
                }
            }

            Section("Standalone bar") {
                Toggle("Show hidden items in a bar of their own", isOn: $settings.preferences.showItemsInBar)
                    .onChange(of: settings.preferences.showItemsInBar) {
                        // Ask for both permissions the moment the feature is turned on, not
                        // piecemeal on a later icon click.
                        if settings.preferences.showItemsInBar { permissions.request() }
                    }
                Text("Clicking Bouncer's icon opens the bar instead of revealing the menu bar. "
                     + "Needs Screen Recording to read the items, and Accessibility to click them.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if settings.preferences.showItemsInBar {
                    PermissionRow(
                        name: "Screen Recording",
                        status: permissions.screenRecording,
                        pane: "Privacy_ScreenCapture",
                        note: "Takes effect after Bouncer restarts."
                    )
                    PermissionRow(
                        name: "Accessibility",
                        status: permissions.accessibility,
                        pane: "Privacy_Accessibility"
                    )

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
                        Text("Match the system appearance").tag(BarStyleChoice.automatic)
                        if #available(macOS 26.0, *) {
                            Text("Liquid Glass").tag(BarStyleChoice.glass)
                        }
                        Text("Custom colour").tag(BarStyleChoice.custom)
                    }
                    if case .automatic = settings.preferences.barStyle {
                        LabeledContent("Colour") {
                            HStack(spacing: 6) {
                                SwatchShape(colour: automaticColour)
                                Text(colorScheme == .dark ? "Dark" : "Light")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if case .custom = settings.preferences.barStyle {
                        LabeledContent("Colour") {
                            HStack(spacing: 6) {
                                ForEach(Self.swatches, id: \.self) { swatch in
                                    SwatchButton(
                                        colour: swatch.colour,
                                        isSelected: swatch.matches(settings.preferences.barStyle),
                                        select: { settings.preferences.barStyle = swatch.style }
                                    )
                                }
                                // No opacity: the bar covers the real icons, and any alpha shows them.
                                ColorPicker("Custom…", selection: barColour, supportsOpacity: false)
                                    .fixedSize()
                            }
                        }
                    }
                }
            }

            Section("Updates") {
                // A dev build, or an updater that failed to start, updates nothing — so it does
                // not offer the choice either.
                if updates.isRunning {
                    Toggle("Check for updates automatically", isOn: $checkForUpdates)
                        .onChange(of: checkForUpdates) {
                            updates.automaticallyChecks = checkForUpdates
                            // Sparkle derives the install choice from this one, so turning checks
                            // back on can flip it under us; re-read rather than show a stale value.
                            installUpdates = updates.automaticallyDownloads
                        }

                    if checkForUpdates {
                        Toggle("Download and install them automatically", isOn: $installUpdates)
                            .onChange(of: installUpdates) { updates.automaticallyDownloads = installUpdates }
                    }
                } else if updates.installChannel == .homebrew {
                    Text("Updates are managed by Homebrew. Run `brew upgrade` to update Bouncer.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Version") {
                    HStack(spacing: 8) {
                        Text(UpdateController.version)
                            .foregroundStyle(.secondary)
                        if updates.isRunning {
                            Button("Check now", action: updates.checkForUpdates)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        // The user grants a permission in System Settings and switches back: re-read then,
        // rather than on a timer.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
        }
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

    /// A colour offered as a swatch, kept in the same sRGB components the preference stores so
    /// selection is an exact comparison rather than a round-trip through `Color`.
    private struct Swatch: Hashable {
        let red: Double
        let green: Double
        let blue: Double

        var colour: Color { Color(.sRGB, red: red, green: green, blue: blue) }
        var style: BarStyle { .custom(red: red, green: green, blue: blue) }

        func matches(_ style: BarStyle) -> Bool { style == self.style }
    }

    private static let swatches: [Swatch] = [
        Swatch(red: 0.11, green: 0.11, blue: 0.12),
        Swatch(red: 0.35, green: 0.35, blue: 0.37),
        Swatch(red: 0.78, green: 0.78, blue: 0.80),
        Swatch(red: 0.78, green: 0.24, blue: 0.24),
        Swatch(red: 0.86, green: 0.53, blue: 0.18),
        Swatch(red: 0.25, green: 0.56, blue: 0.31),
        Swatch(red: 0.20, green: 0.45, blue: 0.78),
        Swatch(red: 0.45, green: 0.32, blue: 0.68)
    ]

    private struct SwatchShape: View {
        let colour: Color

        var body: some View {
            Circle()
                .fill(colour)
                .frame(width: 16, height: 16)
                .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
        }
    }

    private struct SwatchButton: View {
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

    /// What `automatic` is painting with right now — the settings window follows the same
    /// appearance the bar reads.
    private var automaticColour: Color {
        Color(white: colorScheme == .dark ? BarStyle.automaticDark : BarStyle.automaticLight)
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

/// One permission's live status, with a shortcut to its System Settings pane while it is
/// missing — the native prompt only re-shows the first time, so a denied permission is
/// fixed there.
private struct PermissionRow: View {
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
