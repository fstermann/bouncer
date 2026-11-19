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
                    RenameField(deck: live.deck, overview: overview, showsColors: !overview.trayIsDesktop)
                } else {
                    DeckLabel(
                        deck: live.deck, count: live.windows.count, font: .system(size: 15, weight: .semibold),
                        countSuffix: " " + noun(live.windows.count), showsDot: !overview.trayIsDesktop
                    )
                }
                Spacer()
                if overview.trayIsDesktop {
                    TrayButton(title: "Rename") { overview.renaming = live.id }
                } else {
                    HStack(spacing: 8) {
                        if overview.view == .windows {
                            TrayButton(title: "Tile all") { overview.tile(live.id) }
                                .opacity(live.windows.isEmpty ? 0.4 : 1)
                        }
                        TrayButton(title: "Rename") { overview.renaming = live.id }
                        TrayButton(title: "Ungroup") { overview.ungroup(live.id) }
                    }
                }
            }
            if live.windows.isEmpty {
                Text(overview.trayIsDesktop
                     ? "No windows on this desktop."
                     : "Drag \(noun(2)) here, or onto this deck above, to add them.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.top, 60)
            }
            HStack(alignment: .top, spacing: width * 0.025) {
                ForEach(Array(live.windows.enumerated()), id: \.element.id) { index, window in
                    TrayCard(window: window, overview: overview, index: index)
                        .opacity(overview.isDragging(window) ? 0.35 : 1)
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

    /// What the tray counts: windows, or in a deck of Spaces, Spaces.
    private func noun(_ count: Int) -> String {
        let word = overview.view == .spaces && !overview.trayIsDesktop ? "Space" : "window"
        return count == 1 ? word : word + "s"
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
            ItemThumbnail(item: window, overview: overview)
                .aspectRatio(16 / 10, contentMode: .fit)
                .overlay {
                    Highlight(isOn: overview.hovered == .trayWindow(window.id) && overview.reorderTarget == nil)
                }
                .overlay(alignment: .topTrailing) { Badge(text: overview.badge(of: [window])) }
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
        .onTapGesture { overview.pick([window]) }
        .onAppear {
            withAnimation(Springs.trayItem.delay(Double(index) * Springs.stagger)) { isShown = true }
        }
    }
}

/// A tray card's picture: the window's, or for a desktop its front window's, or "Empty".
struct ItemThumbnail: View {
    let item: WindowInfo
    let overview: Overview

    var body: some View {
        if SpaceItems.isDesktop(item) {
            if let front = overview.space(of: item)?.windows.first {
                WindowThumbnail(icon: overview.icon(of: front), picture: overview.thumbnails[front.id])
            } else {
                RoundedRectangle(cornerRadius: Metrics.cornerRadius)
                    .strokeBorder(.white.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .overlay { Text("Empty").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)) }
            }
        } else {
            WindowThumbnail(icon: overview.icon(of: item), picture: overview.thumbnails[item.id])
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
    var showsColors = true
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
            ForEach(showsColors ? DeckColor.allCases : [], id: \.self) { color in
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
