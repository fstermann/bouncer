import AppKit
import Settings
import StandaloneBar
import SwiftUI
import Updates

/// Every setting on one page: the modes first, then what they share, then each mode's own.
struct SettingsForm: View {
    @Bindable var settings: SettingsStore
    let updates: UpdateController
    @Bindable var permissions: StandaloneBarPermissions
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
            Section("Modes", systemImage: "switch.2") {
                ForEach(Mode.allCases) { mode in
                    Toggle(isOn: mode.binding(in: $settings.preferences)) {
                        Text(mode.title)
                        Text(mode.detail)
                    }
                    .disabled(mode.isLastOn(in: settings.preferences))
                }
            }
            generalSection
            notchSection
            if settings.preferences.enableMenuBarItems { menuBarItemsSection }
            if settings.preferences.enableTodos { TodoOptions(preferences: $settings.preferences) }
            updatesSection
        }
        .formStyle(.grouped)
        // The user grants a permission in System Settings and switches back: re-read then,
        // rather than on a timer.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
        }
    }

    @ViewBuilder private var generalSection: some View {
        Section("General", systemImage: "gearshape") {
            Toggle("Launch Bouncer at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { LaunchAtLogin.isEnabled = launchAtLogin }

            Toggle("Show Bouncer in the menu bar", isOn: $settings.preferences.showBouncerIcon)
        }
    }

    @ViewBuilder private var notchSection: some View {
        Section("Notch", systemImage: "macbook") {
            HoverRevealOptions(preferences: $settings.preferences)

            Toggle("Animate the panel", isOn: $settings.preferences.animateBar)
            if settings.preferences.animateBar {
                Slider(value: animationMilliseconds, in: 60...500, step: 20) {
                    Text("Speed")
                } minimumValueLabel: {
                    Text("Fast")
                } maximumValueLabel: {
                    Text("Slow")
                }
            }
        }
    }

    @ViewBuilder private var menuBarItemsSection: some View {
        Section("Menu bar items", systemImage: "menubar.rectangle") {
            Toggle("Enable an always-hidden section", isOn: $settings.preferences.enableAlwaysHiddenSection)
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

            Toggle(isOn: $settings.preferences.showItemsInBar) {
                Text("Show hidden items under the notch")
                Text("Clicking Bouncer's icon opens them in a panel instead of revealing the menu bar. "
                     + "Needs Screen Recording to read the items, and Accessibility to click them.")
            }
            .onChange(of: settings.preferences.showItemsInBar) {
                // Ask for both permissions the moment the feature is turned on, not
                // piecemeal on a later icon click.
                if settings.preferences.showItemsInBar { permissions.request() }
            }

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
            }
        }
    }

    @ViewBuilder private var updatesSection: some View {
        Section("Updates", systemImage: "arrow.down.circle") {
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
