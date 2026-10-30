import SwiftUI

/// A meeting's tags, people or project as chips, and a field that adds one. What is known is offered
/// as the field is typed into, all of it while it is empty; Return or Tab takes the highlighted
/// one, or else what is typed, as do the `breaks` keys. A click on a chip takes it off, as does
/// Delete in the empty field.
struct ChipField: View {
    let placeholder: String
    @Binding var items: [String]
    /// What is offered for what is typed, leaving out the items chosen.
    let offered: (String, [String]) -> [String]
    /// The item typed, or `nil` for none.
    let item: (String) -> String?
    /// Keys that end an item as Return does: a space ends a tag, but not a name.
    var breaks = ","
    /// Holds one item, which another replaces.
    var isSingle = false
    /// Drawn as a tag's chip, in its colour and after the tags it nests under.
    var color: ((String) -> Color?)?
    @State private var typed = ""
    /// None until something is typed or an arrow pressed, so Return in the empty field takes nothing.
    @State private var highlight: Int?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                ForEach(items, id: \.self) { item in
                    Button { items.removeAll { $0 == item } } label: { chip(item) }
                        .buttonStyle(.plain)
                        .fixedSize()
                        .help("Remove")
                }
                field
            }
            if isFocused, !shown.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(shown.enumerated()), id: \.element) { index, item in
                        Button { add(item) } label: { chip(item, isSelected: index == highlight) }
                            .buttonStyle(.plain)
                            .fixedSize()
                    }
                }
            }
        }
        .onChange(of: typed) { highlight = $1.isEmpty ? nil : 0 }
        .onChange(of: isFocused) { if !$1 { add(typed) } }
    }

    private func chip(_ item: String, isSelected: Bool = false) -> Chip {
        guard let color else { return Chip(text: item, isSelected: isSelected) }
        return Chip(tag: item, color: color(item), isSelected: isSelected)
    }

    private var field: some View {
        TextField(items.isEmpty ? placeholder : "", text: $typed)
            .textFieldStyle(.plain)
            .frame(minWidth: 60)
            .focused($isFocused)
            .onKeyPress(.return) { take() }
            .onKeyPress(.tab) { take() }
            // Taken before the field gets them: what it holds cannot be reset while a key changes it.
            .onKeyPress(characters: CharacterSet(charactersIn: breaks), phases: .down) { _ in
                add(typed)
                return .handled
            }
            .onKeyPress(.downArrow) { move(by: 1) }
            .onKeyPress(.upArrow) { move(by: -1) }
            // The Delete key sends U+007F, not the U+0008 `.delete` holds.
            .onKeyPress(keys: [.delete, KeyEquivalent("\u{7F}")]) { _ in
                guard typed.isEmpty, !items.isEmpty else { return .ignored }
                items.removeLast()
                return .handled
            }
    }

    private var shown: [String] {
        Array(offered(typed, items).prefix(5))
    }

    private func take() -> KeyPress.Result {
        if let highlight, shown.indices.contains(highlight) {
            add(shown[highlight])
        } else if item(typed) != nil {
            add(typed)
        } else {
            return .ignored
        }
        return .handled
    }

    private func add(_ text: String) {
        typed = ""
        highlight = nil
        guard let new = item(text), !items.contains(new) else { return }
        items = isSingle ? [new] : items + [new]
    }

    private func move(by step: Int) -> KeyPress.Result {
        guard !shown.isEmpty else { return .ignored }
        highlight = ((highlight ?? (step > 0 ? -1 : 0)) + step + shown.count) % shown.count
        return .handled
    }
}
