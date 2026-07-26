import MenuBar
import Settings
import SwiftUI

public struct SettingsView: View {
    @Bindable private var settings: SettingsStore
    private let manager: MenuBarManager

    public init(settings: SettingsStore, manager: MenuBarManager) {
        _settings = Bindable(settings)
        self.manager = manager
    }

    public var body: some View {
        TabView {
            GeneralSettingsView(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
            LayoutSettingsView(settings: settings, manager: manager)
                .tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }
            ShortcutSettingsView(settings: settings)
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .frame(width: 460)
        .scenePadding()
    }
}
