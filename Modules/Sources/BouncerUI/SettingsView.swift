import Settings
import SwiftUI

public struct SettingsView: View {
    @Bindable private var settings: SettingsStore

    public init(settings: SettingsStore) {
        _settings = Bindable(settings)
    }

    public var body: some View {
        GeneralSettingsView(settings: settings)
            .frame(width: 460)
    }
}
