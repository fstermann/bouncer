import Settings
import SwiftUI

/// The springs the overview moves by, at the mockup's timings.
enum Springs {
    static let fan = Animation.spring(duration: 0.25, bounce: 0.15)
    static let tray = Animation.spring(duration: 0.22, bounce: 0)
    static let trayItem = Animation.spring(duration: 0.28, bounce: 0)
    /// Between one tray card and the next coming in.
    static let stagger: TimeInterval = 0.05
}

/// A deck in the grid: up to three of its windows stacked and offset, fanned out while it is the
/// one the tray shows, its badge on the corner, over its name and its apps' icons.
struct DeckStack: View {
    let live: LiveDeck
    let overview: Overview
    let isActive: Bool

    var body: some View {
        VStack(spacing: 9) {
            ZStack {
                if live.windows.isEmpty {
                    RoundedRectangle(cornerRadius: Metrics.cornerRadius + 1)
                        .strokeBorder(.white.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                } else {
                    let stack = Array(live.windows.prefix(3).enumerated()).reversed()
                    ForEach(stack, id: \.element.id) { depth, window in
                        let layer = StackLayer(depth: depth, isFanned: isActive)
                        ItemThumbnail(item: window, overview: overview)
                            .brightness(Self.brightness[depth])
                            .scaleEffect(layer.scale)
                            .rotationEffect(.degrees(layer.rotation))
                            .offset(layer.offset)
                            .overlay {
                                if depth == 0 { Highlight(isOn: isActive) }
                            }
                    }
                }
            }
            .frame(width: Metrics.card.width, height: Metrics.card.height)
            .overlay(alignment: .topTrailing) { Badge(text: overview.badge(of: live.windows)) }
            .overlay(alignment: .bottomLeading) { DeckBadge(deck: live.deck).offset(x: -7, y: 9) }
            .animation(Springs.fan, value: isActive)
            HStack(spacing: 6) {
                Text(live.deck.name)
                AppIconRow(windows: overview.appWindows(of: live.windows), overview: overview)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.4), radius: 1.5, y: 1)
            .lineLimit(1)
        }
        .contentShape(Rectangle())
    }

    /// CSS's `brightness(.85)` and `brightness(.7)`, as SwiftUI's additive brightness.
    static let brightness: [Double] = [0, -0.12, -0.25]
}

/// A desktop in the Spaces view: up to three of its windows stacked as a deck's are, over its name and
/// window count. Hovering it opens the tray on its windows.
struct DesktopStack: View {
    let desktop: WindowInfo
    let overview: Overview
    let isActive: Bool

    var body: some View {
        let windows = overview.space(of: desktop)?.windows ?? []
        VStack(spacing: 9) {
            ZStack {
                if windows.isEmpty {
                    RoundedRectangle(cornerRadius: Metrics.cornerRadius + 1)
                        .strokeBorder(.white.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .overlay {
                            Text("Empty")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                } else {
                    let stack = Array(windows.prefix(3).enumerated()).reversed()
                    ForEach(stack, id: \.element.id) { depth, window in
                        let layer = StackLayer(depth: depth, isFanned: isActive)
                        WindowThumbnail(icon: overview.icon(of: window), picture: overview.thumbnails[window.id])
                            .brightness(DeckStack.brightness[depth])
                            .scaleEffect(layer.scale)
                            .rotationEffect(.degrees(layer.rotation))
                            .offset(layer.offset)
                            .overlay {
                                if depth == 0 { Highlight(isOn: isActive) }
                            }
                    }
                }
            }
            .frame(width: Metrics.card.width, height: Metrics.card.height)
            .overlay(alignment: .topTrailing) { Badge(text: overview.badge(of: [desktop])) }
            .overlay(alignment: .topLeading) { removeButton }
            .animation(Springs.fan, value: isActive)
            HStack(spacing: 6) {
                Text(desktop.label)
                Text("\(windows.count)")
                    .font(.system(size: 10.5))
                    .padding(.horizontal, 6)
                    .background(.white.opacity(0.25), in: Capsule())
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.4), radius: 1.5, y: 1)
            .lineLimit(1)
        }
        .contentShape(Rectangle())
    }
}

extension DesktopStack {
    /// Mission Control's close button, over the corner while the pointer is on a desktop that can go.
    @ViewBuilder private var removeButton: some View {
        let isOver = overview.hovered == .removeDesktop(desktop.id)
        if overview.drag == nil, isOver || overview.hovered == .desktop(desktop.id),
           let space = overview.removable(desktop) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.black.opacity(0.75))
                .frame(width: 20, height: 20)
                .background(.white.opacity(isOver ? 1 : 0.85), in: Circle())
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                .padding(6)
                .hoverTarget(.removeDesktop(desktop.id))
                .contentShape(Rectangle())
                .onTapGesture { overview.onRemoveDesktop?(space) }
        }
    }
}

/// Where the window `depth` back from the front of a stack sits, at rest and fanned out.
struct StackLayer: Equatable {
    var offset: CGSize = .zero
    var scale: CGFloat = 1
    var rotation: Double = 0

    init(depth: Int, isFanned: Bool) {
        switch (depth, isFanned) {
        case (1, false): (offset, scale) = (CGSize(width: 5, height: -5), 0.97)
        case (1, true): (offset, scale, rotation) = (CGSize(width: 9, height: -7), 0.96, 1.5)
        case (2, false): (offset, scale) = (CGSize(width: 10, height: -10), 0.94)
        case (2, true): (offset, scale, rotation) = (CGSize(width: 18, height: -14), 0.92, 3)
        default: break
        }
    }
}

/// A deck's badge, name and count, as the tray head shows it.
struct DeckLabel: View {
    let deck: Deck
    let count: Int
    let font: Font
    var countSuffix = ""
    var showsBadge = true

    var body: some View {
        HStack(spacing: 6) {
            if showsBadge {
                DeckBadge(deck: deck, size: 20)
            }
            Text(deck.name)
            Text("\(count)\(countSuffix)")
                .font(.system(size: 10.5))
                .padding(.horizontal, 6)
                .background(.white.opacity(0.25), in: Capsule())
        }
        .font(font)
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.4), radius: 1.5, y: 1)
        .lineLimit(1)
    }
}

/// The blue ring round the card under the pointer.
struct Highlight: View {
    let isOn: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: Metrics.cornerRadius + 2)
            .inset(by: -3.5)
            .stroke(Metrics.highlight, lineWidth: 3)
            .opacity(isOn ? 1 : 0)
    }
}

/// The drop bar at the bottom of the display while a window is dragged that can change full screen: a
/// desktop's window dropped on it enters full screen, a full screen Space dropped on it leaves it.
struct FullScreenBar: View {
    let change: Overview.FullScreenChange
    let isHovered: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: change == .leave
                  ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
            Text(change == .leave ? "Leave full screen" : "Full screen")
        }
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(.white)
        .frame(width: 420, height: 64)
        .background(.black.opacity(isHovered ? 0.45 : 0.3), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    isHovered ? Metrics.highlight : .white.opacity(0.6),
                    style: StrokeStyle(lineWidth: isHovered ? 3 : 1.5, dash: isHovered ? [] : [5, 4])
                )
        }
        .contentShape(Rectangle())
    }
}

/// The last tile in the grid, which starts an empty deck.
struct NewDeckTile: View {
    var title = "+ New group"
    let isHovered: Bool

    var body: some View {
        VStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.white.opacity(isHovered ? 0.8 : 0.45), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .overlay {
                    Text(title)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .frame(width: Metrics.card.width, height: Metrics.card.height)
            Text(" ")
                .font(.system(size: 12, weight: .medium))
        }
        .contentShape(Rectangle())
    }
}

/// The window being dragged, following the pointer.
struct DragGhost: View {
    let window: WindowInfo
    let picture: NSImage?
    let point: CGPoint
    let overview: Overview

    var body: some View {
        WindowThumbnail(icon: overview.icon(of: window), picture: picture)
            .frame(width: Metrics.card.width * 0.8, height: Metrics.card.height * 0.8)
            .rotationEffect(.degrees(-3))
            .opacity(0.9)
            .position(point)
            .allowsHitTesting(false)
    }
}

/// The outline over a display while a window from another display's overview is dragged over it.
struct DisplayDrop: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 18)
            .strokeBorder(Metrics.highlight, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
            .overlay(alignment: .bottom) {
                Text("Move to this display")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.35), in: Capsule())
                    .padding(.bottom, 40)
            }
            .padding(12)
            .allowsHitTesting(false)
    }
}
