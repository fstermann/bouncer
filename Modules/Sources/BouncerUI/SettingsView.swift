import Settings
import SwiftUI
import Updates

public struct SettingsView: View {
    @Bindable private var settings: SettingsStore
    private let updates: UpdateController

    public init(settings: SettingsStore, updates: UpdateController) {
        _settings = Bindable(settings)
        self.updates = updates
    }

    public var body: some View {
        GeneralSettingsView(settings: settings, updates: updates)
            .frame(width: 460)
    }
}
