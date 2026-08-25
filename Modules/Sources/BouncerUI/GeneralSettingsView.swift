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
    @State private var selection: Pane = .general

    init(settings: SettingsStore, updates: UpdateController, permissions: StandaloneBarPermissions) {
        _settings = Bindable(settings)
        self.updates = updates
        _permissions = Bindable(permissions)
        _checkForUpdates = State(initialValue: updates.automaticallyChecks)
        _installUpdates = State(initialValue: updates.automaticallyDownloads)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 2) {
                ForEach(Pane.allCases) { pane in
                    SidebarRow(pane: pane, isSelected: selection == pane) { selection = pane }
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.top, 38)
            .padding(.bottom, 8)
            .frame(minWidth: 200, maxWidth: 200, maxHeight: .infinity, alignment: .top)
            .background(Color.primary.opacity(0.05))

            Divider()

            Form {
                switch selection {
                case .general: generalPane
                case .revealing: revealingPane
                case .standaloneBar: standaloneBarPane
                case .updates: updatesPane
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity)
            .padding(.top, 30)
        }
        .ignoresSafeArea()
        // The user grants a permission in System Settings and switches back: re-read then,
        // rather than on a timer.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
        }
    }

    @ViewBuilder private var generalPane: some View {
        Section {
            Toggle("Launch Bouncer at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { LaunchAtLogin.isEnabled = launchAtLogin }

            Toggle("Show Bouncer in the menu bar", isOn: $settings.preferences.showBouncerIcon)
            Toggle("Enable an always-hidden section", isOn: $settings.preferences.enableAlwaysHiddenSection)
        }
    }

    @ViewBuilder private var revealingPane: some View {
        Section {
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
    }

    @ViewBuilder private var standaloneBarPane: some View {
        Section {
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
        }

        if settings.preferences.showItemsInBar {
            Section("Permissions") {
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
            }

            Section("Appearance") {
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
                            ForEach(swatches, id: \.self) { swatch in
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
    }

    @ViewBuilder private var updatesPane: some View {
        Section {
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
