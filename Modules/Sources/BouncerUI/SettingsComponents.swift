import AppKit
import MenuBar
import Settings
import StandaloneBar
import SwiftUI
import Todos
import UniformTypeIdentifiers

/// What Bouncer does: hide menu bar items, show todos, or both. At least one is always on.
enum Mode: CaseIterable, Identifiable {
    case menuBarItems, todos

    var id: Self { self }

    var title: String {
        switch self {
        case .menuBarItems: "Menu bar items"
        case .todos: "Todos"
        }
    }

    var symbol: String {
        switch self {
        case .menuBarItems: "menubar.rectangle"
        case .todos: "checklist"
        }
    }

    var detail: String {
        switch self {
        case .menuBarItems: "Hide menu bar items behind dividers and reveal them when you need them."
        case .todos: "Keep a todo list from a Markdown file under the notch."
        }
    }

    private var keyPath: WritableKeyPath<Preferences, Bool> {
        switch self {
        case .menuBarItems: \.enableMenuBarItems
        case .todos: \.enableTodos
        }
    }

    func binding(in preferences: Binding<Preferences>) -> Binding<Bool> {
        preferences[dynamicMember: keyPath]
    }

    /// Switching it off would leave Bouncer doing nothing.
    func isLastOn(in preferences: Preferences) -> Bool {
        preferences[keyPath: keyPath] && Self.allCases.allSatisfy { $0 == self || !preferences[keyPath: $0.keyPath] }
    }
}

extension Section where Parent == Label<Text, Image>, Footer == EmptyView, Content: View {
    /// A section headed by its title and an SF Symbol.
    init(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.init(content: content) { Label(title, systemImage: systemImage) }
    }
}

/// One permission's live status, with a shortcut to its System Settings pane while it is
/// missing — the native prompt only re-shows the first time, so a denied permission is
/// fixed there.
struct PermissionRow: View {
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

/// Revealing by pointer alone, and how long it waits first: the Dock's own delay, or one of the
/// user's. Custom starts from the Dock's, so switching to it changes nothing until the slider moves.
struct HoverRevealOptions: View {
    @Binding var preferences: Preferences

    var body: some View {
        Picker(selection: reach) {
            Text("Off").tag(Reach.off)
            Text("At the notch").tag(Reach.notch)
            if preferences.enableMenuBarItems {
                Text("Anywhere in the menu bar").tag(Reach.menuBar)
            }
        } label: {
            Text("Reveal on hover")
            Text(reachDetail)
        }
        if reach.wrappedValue != .off {
            delayPicker
        }
    }

    /// Where hover reveals. The whole menu bar takes in the notch, which still opens the todo page.
    private enum Reach: Hashable {
        case off, notch, menuBar
    }

    /// Hover over the whole menu bar means nothing without menu bar items, so it reads as the notch.
    private var reach: Binding<Reach> {
        Binding {
            if preferences.enableMenuBarItems, preferences.revealOnHover { return .menuBar }
            return preferences.revealNearNotch || preferences.revealOnHover ? .notch : .off
        } set: { reach in
            preferences.revealOnHover = reach == .menuBar
            preferences.revealNearNotch = reach != .off
        }
    }

    private var reachDetail: String {
        let notch = preferences.enableTodos ? "The notch opens the todos" : "The notch reveals hidden items"
        return "\(notch) and closes when the pointer leaves. Without a notch, the top centre of the menu bar."
    }

    @ViewBuilder private var delayPicker: some View {
        Picker("Delay before revealing", selection: followsDock) {
            Text("Match the Dock (\(Self.label(DockDelay.current)))").tag(true)
            Text("Custom").tag(false)
        }
        if case .seconds(let seconds) = preferences.hoverDelay {
            Slider(value: custom, in: 0...HoverDelay.longest, step: 0.01) {
                Text(Self.label(seconds))
            } minimumValueLabel: {
                Text("0 ms")
            } maximumValueLabel: {
                Text("\(Int(HoverDelay.longest))s")
            }
        }
    }

    private var followsDock: Binding<Bool> {
        Binding { preferences.hoverDelay == .matchDock } set: { matches in
            preferences.hoverDelay = matches ? .matchDock : .seconds(min(DockDelay.current, HoverDelay.longest))
        }
    }

    private var custom: Binding<Double> {
        Binding {
            guard case .seconds(let seconds) = preferences.hoverDelay else { return 0 }
            return seconds
        } set: { preferences.hoverDelay = .seconds($0) }
    }

    private static func label(_ seconds: TimeInterval) -> String {
        "\(Int((seconds * 1000).rounded())) ms"
    }
}

/// The todo file the notch panel's todo page reads and writes.
struct TodoOptions: View {
    @Binding var preferences: Preferences

    var body: some View {
        Section("Todos", systemImage: "checklist") {
            LabeledContent("File") {
                HStack(spacing: 8) {
                    Text(fileName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose…", action: choose)
                    if preferences.todoFile != nil {
                        Button("Use Local") { preferences.todoFile = nil }
                    }
                }
            }
            Text("Bouncer shows the open `- [ ]` lines of this Markdown file under the notch, and adds new "
                 + "ones at its end. Without a chosen file, it keeps them in a local one. Hover near the notch "
                 + "or press ⌘⇧B to open it.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var fileName: String {
        guard let bookmark = preferences.todoFile else { return "Local" }
        return TodoController.url(of: bookmark)?.lastPathComponent ?? "Not found"
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url, let bookmark = TodoController.bookmark(for: url)
        else { return }
        preferences.todoFile = bookmark
    }
}
