import SwiftUI

/// A meeting's tags as a todo's show, coloured and after the tags they nest under, and a field
/// that adds one. The known tags are offered as the field is typed into, all of them while it is
/// empty; Return or Tab takes the highlighted one, or else what is typed, as do a space and a
/// comma. A click on a chip takes its tag off, as does Delete in the empty field.
struct NoteTagField: View {
    @Binding var tags: [String]
    let known: NoteSuggestions
    @State private var typed = ""
    /// None until something is typed or an arrow pressed, so Return in the empty field takes nothing.
    @State private var highlight: Int?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                ForEach(tags, id: \.self) { tag in
                    Button { tags.removeAll { $0 == tag } } label: { Chip(tag: tag, color: known.color(of: tag)) }
                        .buttonStyle(.plain)
                        .fixedSize()
                        .help("Remove tag")
                }
                field
            }
            if isFocused, !shown.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(shown.enumerated()), id: \.element) { index, tag in
                        Button { add(tag) } label: {
                            Chip(tag: tag, color: known.color(of: tag), isSelected: index == highlight)
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                    }
                }
            }
        }
        .onChange(of: typed) { highlight = $1.isEmpty ? nil : 0 }
        .onChange(of: isFocused) { if !$1 { add(typed) } }
    }

    private var field: some View {
        TextField(tags.isEmpty ? "Tags" : "", text: $typed)
            .textFieldStyle(.plain)
            .frame(minWidth: 60)
            .focused($isFocused)
            .onKeyPress(.return) { take() }
            .onKeyPress(.tab) { take() }
            // Taken before the field gets them: what it holds cannot be reset while a key changes it.
            .onKeyPress(characters: CharacterSet(charactersIn: " ,"), phases: .down) { _ in
                add(typed)
                return .handled
            }
            .onKeyPress(.downArrow) { move(by: 1) }
            .onKeyPress(.upArrow) { move(by: -1) }
            // The Delete key sends U+007F, not the U+0008 `.delete` holds.
            .onKeyPress(keys: [.delete, KeyEquivalent("\u{7F}")]) { _ in
                guard typed.isEmpty, !tags.isEmpty else { return .ignored }
                tags.removeLast()
                return .handled
            }
    }

    private var shown: [String] {
        Array(TagCompletion.suggestions(for: typed, carrying: tags, from: known.tags).prefix(5))
    }

    private func take() -> KeyPress.Result {
        if let highlight, shown.indices.contains(highlight) {
            add(shown[highlight])
        } else if TagCompletion.tag(from: typed) != nil {
            add(typed)
        } else {
            return .ignored
        }
        return .handled
    }

    private func add(_ text: String) {
        typed = ""
        highlight = nil
        guard let tag = TagCompletion.tag(from: text), !tags.contains(tag) else { return }
        tags.append(tag)
    }

    private func move(by step: Int) -> KeyPress.Result {
        guard !shown.isEmpty else { return .ignored }
        highlight = ((highlight ?? (step > 0 ? -1 : 0)) + step + shown.count) % shown.count
        return .handled
    }
}
