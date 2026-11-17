import Decks
import Settings
import StandaloneBar
import SwiftUI
import Updates

public struct SettingsView: View {
    @Bindable private var settings: SettingsStore
    private let updates: UpdateController
    private let permissions: StandaloneBarPermissions
    private let decksPermissions: DecksPermissions

    public init(
        settings: SettingsStore, updates: UpdateController, permissions: StandaloneBarPermissions,
        decksPermissions: DecksPermissions
    ) {
        _settings = Bindable(settings)
        self.updates = updates
        self.permissions = permissions
        self.decksPermissions = decksPermissions
    }

    public var body: some View {
        SettingsForm(
            settings: settings, updates: updates, permissions: permissions, decksPermissions: decksPermissions
        )
            .frame(width: 520, height: 640)
    }
}
