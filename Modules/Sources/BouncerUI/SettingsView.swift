import Settings
import StandaloneBar
import SwiftUI
import Updates

public struct SettingsView: View {
    @Bindable private var settings: SettingsStore
    private let updates: UpdateController
    private let permissions: StandaloneBarPermissions

    public init(settings: SettingsStore, updates: UpdateController, permissions: StandaloneBarPermissions) {
        _settings = Bindable(settings)
        self.updates = updates
        self.permissions = permissions
    }

    public var body: some View {
        SettingsForm(settings: settings, updates: updates, permissions: permissions)
            .frame(width: 520, height: 640)
    }
}
