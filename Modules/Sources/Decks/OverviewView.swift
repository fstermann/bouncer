import Settings
import SwiftUI

/// The overview's content: the dimmed, blurred desktop, a hint, the decks and windows, and under the
/// row of the deck the pointer is on, that deck's tray.
struct OverviewView: View {
    let overview: Overview

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                backdrop
                ScrollView {
                    VStack(spacing: 0) {
                        if overview.hasSpaces {
                            ViewSwitch(overview: overview)
                                .padding(.bottom, 12)
                        }
                        hint
                        if !overview.canRaise || !overview.canSeeTitles {
                            PermissionBanner(overview: overview)
                                .padding(.top, 18)
                        }
                        grid(trayWidth: min(1000, geometry.size.width * 0.92), width: geometry.size.width)
                            .padding(.top, 18)
                    }
                    .padding(.vertical, 28)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .top)
                    .background {
                        Color.clear.contentShape(Rectangle()).onTapGesture { overview.onDismiss?() }
                    }
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                if let drag = overview.drag, drag.isMoving { DragGhost(drag: drag, overview: overview) }
            }
        }
        .coordinateSpace(name: Hover.space)
        .onPreferenceChange(HoverFrames.self) { frames in
            MainActor.assumeIsolated { overview.hoverFrames = frames }
        }
        .ignoresSafeArea()
    }

    /// The mockup's hidden tray: faded out, 14 pt higher and at 98 %, from its top edge.
    private static let trayTransition = AnyTransition.opacity
        .combined(with: .offset(y: -14))
        .combined(with: .scale(scale: 0.98, anchor: .top))

    /// One tile of the grid, or the tray between two rows of them.
    private enum Tile: Identifiable {
        case deck(LiveDeck)
        case item(WindowInfo)
        case newDeck
        case tray(LiveDeck)

        var id: String {
            switch self {
            case .deck(let live): "deck-\(live.id)"
            case .item(let item): "item-\(item.id)"
            case .newDeck: "new"
            case .tray: "tray"
            }
        }
    }

    /// The tiles in order, the tray after the last tile of the row holding the tile it shows, so it opens
    /// right under that tile however many rows there are.
    private func tiles(width: CGFloat) -> [Tile] {
        let arrangement = overview.arrangement
        var tiles: [Tile] = arrangement.decks.map(Tile.deck) + arrangement.ungrouped.map(Tile.item) + [.newDeck]
        guard let live = overview.trayShows,
              let index = tiles.firstIndex(where: { trayID(of: $0) == live.id })
        else { return tiles }
        let perRow = itemsPerRow(count: tiles.count, itemWidth: Metrics.card.width, spacing: Metrics.gap, width: width)
        tiles.insert(.tray(live), at: min(tiles.count, (index / perRow + 1) * perRow))
        return tiles
    }

    private func trayID(of tile: Tile) -> UUID? {
        switch tile {
        case .deck(let live): live.id
        case .item(let item) where overview.view == .spaces && SpaceItems.isDesktop(item): Overview.trayID(of: item.id)
        default: nil
        }
    }

    private func grid(trayWidth: CGFloat, width: CGFloat) -> some View {
        CenteredFlow(spacing: Metrics.gap, lineSpacing: Metrics.gap) {
            ForEach(tiles(width: width - 60)) { tile in
                switch tile {
                case .deck(let live):
                    DeckStack(
                        live: live, overview: overview,
                        isActive: overview.trayDeck == live.id || isDropTarget(.deck(live.id))
                    )
                    .hoverTarget(.deck(live.id))
                    .onTapGesture { overview.pick(live.windows.reversed()) }
                case .item(let item) where overview.view == .spaces && SpaceItems.isDesktop(item):
                    DesktopStack(
                        desktop: item, overview: overview, isActive: overview.trayDeck == Overview.trayID(of: item.id)
                    )
                    .hoverTarget(.desktop(item.id))
                    .onTapGesture { overview.pick([item]) }
                case .item(let item):
                    windowCard(item)
                case .newDeck:
                    NewDeckTile(isHovered: overview.hovered == .newDeck)
                        .hoverTarget(.newDeck)
                        .onTapGesture { overview.newDeck() }
                case .tray(let live):
                    DeckTray(live: live, overview: overview, width: trayWidth)
                        .hoverTarget(.tray)
                        .frame(maxWidth: .infinity)
                        .flowRow()
                        .transition(Self.trayTransition)
                }
            }
        }
        .animation(Springs.tray, value: overview.trayDeck)
        .hoverTarget(.grid)
        .padding(.horizontal, 30)
    }

    private func windowCard(_ window: WindowInfo) -> some View {
        WindowCard(
            window: window, place: overview.view == .windows ? overview.place(of: window) : nil,
            badge: overview.badge(of: [window]),
            icon: overview.icon(of: window), picture: overview.thumbnails[window.id],
            isHovered: overview.hovered == .window(window.id) && !overview.isDragging(window)
        ) { overview.pick([window]) }
        .hoverTarget(.window(window.id))
        .opacity(overview.isDragging(window) ? 0.35 : 1)
    }

    /// Whether a window being dragged would drop on `target`.
    private func isDropTarget(_ target: HoverTarget) -> Bool {
        overview.drag?.isMoving == true && overview.hovered == target
    }

    private var backdrop: some View {
        ZStack {
            Color.black
            if let wallpaper = overview.wallpaper {
                // Sized by the panel, not the picture: the image's own size would grow the window past the display.
                Color.clear.overlay {
                    Image(nsImage: wallpaper)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 14 * 2, opaque: true)
                }
                .clipped()
            }
            Color(red: 40 / 255, green: 20 / 255, blue: 8 / 255).opacity(0.35)
        }
    }

    private var hint: some View {
        let what = overview.view == .windows ? "window" : "Space"
        let tab = overview.hasSpaces ? "  ·  tab to switch view" : ""
        return Text("Hover a deck to expand it  ·  click a \(what) to go to it  ·  "
             + "drag a \(what) onto another to group them\(tab)  ·  esc to close")
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.75))
    }
}

enum Metrics {
    static let card = CGSize(width: 190, height: 118)
    static let gap: CGFloat = 26
    static let cornerRadius: CGFloat = 7
    static let highlight = Color(red: 0x3B / 255, green: 0x82 / 255, blue: 0xF6 / 255)
}

/// One ungrouped window: its picture, or its app's icon until there is one, over its title.
struct WindowCard: View {
    let window: WindowInfo
    /// Where the window lives when that is not the current Space.
    let place: String?
    let badge: String?
    let icon: NSImage
    let picture: NSImage?
    let isHovered: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 9) {
            WindowThumbnail(icon: icon, picture: picture)
                .frame(width: Metrics.card.width, height: Metrics.card.height)
                .overlay { Highlight(isOn: isHovered) }
                .overlay(alignment: .topLeading) {
                    if let place { PlaceTag(text: place).padding(6) }
                }
                .overlay(alignment: .topTrailing) { Badge(text: badge) }
            Text(window.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 1.5, y: 1)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: Metrics.card.width)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}

/// The two views' names above the grid, the current one lit; a click or Tab switches.
struct ViewSwitch: View {
    let overview: Overview

    var body: some View {
        HStack(spacing: 4) {
            segment("Windows", .windows)
            segment("Spaces", .spaces)
        }
        .padding(3)
        .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }

    private func segment(_ title: String, _ kind: DeckKind) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(overview.view == kind ? 1 : 0.6))
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(.white.opacity(overview.view == kind ? 0.2 : 0), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onTapGesture { overview.view = kind }
    }
}

/// An app's Dock badge, at a card's top right corner as the Dock draws it.
struct Badge: View {
    let text: String?

    var body: some View {
        if let text {
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .frame(minWidth: 20, minHeight: 20)
                .background(Color(red: 1, green: 0x3B / 255, blue: 0x30 / 255), in: Capsule())
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                .offset(x: 7, y: -7)
        }
    }
}

/// The small label on a card that says which Space its window is on.
struct PlaceTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.black.opacity(0.55), in: Capsule())
    }
}

/// A window's picture, fitted into the card, or until it arrives a dark card with its app's icon.
struct WindowThumbnail: View {
    let icon: NSImage
    let picture: NSImage?

    var body: some View {
        RoundedRectangle(cornerRadius: Metrics.cornerRadius)
            .fill(Color(red: 0x1E / 255, green: 0x1F / 255, blue: 0x24 / 255))
            .overlay {
                if let picture {
                    Image(nsImage: picture)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                } else {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 48, height: 48)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.cornerRadius)
                    .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.45), radius: 15, y: 10)
    }
}

/// Says what is missing and opens its pane: without Accessibility a click raises nothing, and
/// without Screen Recording windows have no titles.
struct PermissionBanner: View {
    let overview: Overview

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .foregroundStyle(.white)
            if !overview.canRaise {
                Button("Grant Accessibility") { overview.onGrant?(.accessibility) }
            }
            if !overview.canSeeTitles {
                Button("Grant Screen Recording") { overview.onGrant?(.screenRecording) }
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }

    private var message: String {
        switch (overview.canRaise, overview.canSeeTitles) {
        case (false, false): "Bouncer needs Accessibility to focus windows, and Screen Recording to show them."
        case (false, true): "Bouncer needs Accessibility to focus windows."
        default: "Bouncer needs Screen Recording to show window titles and pictures."
        }
    }
}

/// The window being dragged, following the pointer.
struct DragGhost: View {
    let drag: Overview.Drag
    let overview: Overview

    var body: some View {
        WindowThumbnail(icon: overview.icon(of: drag.window), picture: overview.thumbnails[drag.window.id])
            .frame(width: Metrics.card.width * 0.8, height: Metrics.card.height * 0.8)
            .rotationEffect(.degrees(-3))
            .opacity(0.9)
            .position(drag.point)
            .allowsHitTesting(false)
    }
}
