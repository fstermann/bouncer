import Settings
import SwiftUI

/// The frosted panel under the grid that shows one deck's windows at a larger size.
struct DeckTray: View {
    let live: LiveDeck
    let overview: Overview
    let width: CGFloat

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                if overview.renaming == live.id {
                    RenameField(deck: live.deck, overview: overview)
                } else {
                    DeckLabel(
                        deck: live.deck, count: live.windows.count, font: .system(size: 15, weight: .semibold),
                        countSuffix: live.windows.count == 1 ? " window" : " windows"
                    )
                }
                Spacer()
                HStack(spacing: 8) {
                    TrayButton(title: "Tile all") { overview.tile(live.id) }
                        .opacity(live.windows.isEmpty ? 0.4 : 1)
                    TrayButton(title: "Rename") { overview.renaming = live.id }
                    TrayButton(title: "Ungroup") { overview.ungroup(live.id) }
                }
            }
            if live.windows.isEmpty {
                Text("⌥ drag windows here, or onto this deck above, to add them.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.top, 60)
            }
            HStack(alignment: .top, spacing: width * 0.025) {
                ForEach(Array(live.windows.enumerated()), id: \.element.id) { index, window in
                    TrayCard(window: window, overview: overview, index: index)
                        .opacity(overview.drag?.window.id == window.id ? 0.35 : 1)
                }
            }
            .frame(maxWidth: .infinity)
            // Each deck brings its cards in afresh rather than morphing the last one's.
            .id(live.id)
        }
        .padding(.top, 18)
        .padding(.horizontal, 26)
        .padding(.bottom, 24)
        .frame(width: width)
        .frame(minHeight: 250, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(.white.opacity(0.12))
                .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.3), lineWidth: 0.5) }
                .shadow(color: .black.opacity(0.25), radius: 30, y: 20)
        }
        .contentShape(Rectangle())
    }
}

/// One of a deck's windows in the tray, fading and sliding in a beat after the one before it.
struct TrayCard: View {
    let window: WindowInfo
    let overview: Overview
    let index: Int
    @State private var isShown = false

    var body: some View {
        VStack(spacing: 9) {
            WindowThumbnail(icon: overview.icon(of: window), picture: overview.thumbnails[window.id])
                .aspectRatio(16 / 10, contentMode: .fit)
                .overlay { Highlight(isOn: overview.hovered == .trayWindow(window.id)) }
            Text(window.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 1.5, y: 1)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: 260)
        .opacity(isShown ? 1 : 0)
        .offset(y: isShown ? 0 : -10)
        .contentShape(Rectangle())
        .hoverTarget(.trayWindow(window.id))
        .onTapGesture { overview.onPick?([window]) }
        .onAppear {
            withAnimation(Springs.trayItem.delay(Double(index) * Springs.stagger)) { isShown = true }
        }
    }
}

struct TrayButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Text(title)
            .font(.system(size: 11.5))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }
}

/// The deck's name as a field, and its colours as swatches beside it. Return or a swatch keeps the
/// name; Escape keeps the old one.
struct RenameField: View {
    let deck: Deck
    let overview: Overview
    @State private var name = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            TextField("Name", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 180)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
                .focused($isFocused)
                .onSubmit { overview.rename(deck.id, to: name) }
                .onExitCommand { overview.renaming = nil }
            ForEach(DeckColor.allCases, id: \.self) { color in
                Circle()
                    .fill(color.color)
                    .frame(width: 14, height: 14)
                    .overlay { Circle().strokeBorder(.white, lineWidth: color == deck.color ? 2 : 0) }
                    .contentShape(Circle())
                    .onTapGesture { overview.recolor(deck.id, to: color) }
            }
        }
        .onAppear {
            name = deck.name
            isFocused = true
        }
    }
}
