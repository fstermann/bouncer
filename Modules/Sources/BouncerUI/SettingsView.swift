import Settings
import StandaloneBar
import SwiftUI
import Updates

public struct SettingsView: View {
    @Bindable private var settings: SettingsStore
    private let updates: UpdateController
    private let permissions: StandaloneBarPermissions
    private let standaloneItemArrangement: StandaloneItemArrangement

    public init(
        settings: SettingsStore,
        updates: UpdateController,
        permissions: StandaloneBarPermissions,
        standaloneItemArrangement: StandaloneItemArrangement
    ) {
        _settings = Bindable(settings)
        self.updates = updates
        self.permissions = permissions
        self.standaloneItemArrangement = standaloneItemArrangement
    }

    public var body: some View {
        GeneralSettingsView(
            settings: settings,
            updates: updates,
            permissions: permissions,
            standaloneItemArrangement: standaloneItemArrangement
        )
            .frame(width: 640, height: 480)
    }
}
