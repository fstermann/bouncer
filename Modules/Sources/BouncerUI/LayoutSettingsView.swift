import MenuBar
import Settings
import SwiftUI

/// Shows which section each menu bar item currently sits in, and puts the dividers on
/// screen so the user can Cmd-drag items between them.
struct LayoutSettingsView: View {
    @Bindable var settings: SettingsStore
    let manager: MenuBarManager

    @State private var layout: [(item: MenuBarItem, section: MenuBarSection)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Arrange menu bar items", isOn: Bindable(manager).isEditingLayout)
            Text("""
                While arranging, Bouncer's dividers appear in the menu bar. Hold ⌘ and drag \
                items across a divider to move them between sections.
                """)
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider()

            if layout.isEmpty {
                ContentUnavailableView(
                    "Nothing to show",
                    systemImage: "menubar.rectangle",
                    description: Text("Turn on arranging to see the current layout.")
                )
                .frame(height: 220)
            } else {
                List {
                    ForEach(sectionsInOrder, id: \.self) { section in
                        Section(section.displayName) {
                            ForEach(layout.filter { $0.section == section }, id: \.item.id) { entry in
                                Text(entry.item.ownerName)
                            }
                        }
                    }
                }
                .frame(height: 220)
            }
        }
        .task(id: manager.isEditingLayout) { await refreshWhileEditing() }
    }

    private var sectionsInOrder: [MenuBarSection] {
        settings.preferences.enableAlwaysHiddenSection
            ? MenuBarSection.allCases
            : [.visible, .hidden]
    }

    /// Item frames only change when the user drags something, and there is no
    /// notification for that — so poll, but only while this pane is arranging.
    private func refreshWhileEditing() async {
        guard manager.isEditingLayout else {
            layout = []
            return
        }
        while !Task.isCancelled {
            layout = manager.currentLayout() ?? []
            try? await Task.sleep(for: .milliseconds(500))
        }
    }
}
