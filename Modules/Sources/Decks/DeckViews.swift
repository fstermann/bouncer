import Settings
import SwiftUI

extension DeckColor {
    var color: Color {
        switch self {
        case .blue: Color(red: 0x60 / 255, green: 0xA5 / 255, blue: 0xFA / 255)
        case .pink: Color(red: 0xF4 / 255, green: 0x72 / 255, blue: 0xB6 / 255)
        case .green: Color(red: 0x34 / 255, green: 0xD3 / 255, blue: 0x99 / 255)
        case .orange: Color(red: 0xFB / 255, green: 0x92 / 255, blue: 0x3C / 255)
        case .purple: Color(red: 0xA7 / 255, green: 0x8B / 255, blue: 0xFA / 255)
        case .yellow: Color(red: 0xFA / 255, green: 0xCC / 255, blue: 0x15 / 255)
        case .red: Color(red: 0xF8 / 255, green: 0x71 / 255, blue: 0x71 / 255)
        case .teal: Color(red: 0x2D / 255, green: 0xD4 / 255, blue: 0xBF / 255)
        }
    }
}

/// The springs the overview moves by, at the mockup's timings.
enum Springs {
    static let fan = Animation.spring(duration: 0.25, bounce: 0.15)
    static let tray = Animation.spring(duration: 0.22, bounce: 0)
    static let trayItem = Animation.spring(duration: 0.28, bounce: 0)
    /// Between one tray card and the next coming in.
    static let stagger: TimeInterval = 0.05
}

/// A deck in the grid: up to three of its windows stacked and offset, fanned out while it is the
/// one the tray shows, over its colour, name and window count.
struct DeckStack: View {
    let live: LiveDeck
    let overview: Overview
    let isActive: Bool

    var body: some View {
        VStack(spacing: 9) {
            ZStack {
                if live.windows.isEmpty {
                    RoundedRectangle(cornerRadius: Metrics.cornerRadius + 1)
                        .strokeBorder(
                            live.deck.color.color.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                        )
                } else {
                    let stack = Array(live.windows.prefix(3).enumerated()).reversed()
                    ForEach(stack, id: \.element.id) { depth, window in
                        let layer = StackLayer(depth: depth, isFanned: isActive)
                        WindowThumbnail(icon: overview.icon(of: window), picture: overview.thumbnails[window.id])
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
            .animation(Springs.fan, value: isActive)
            DeckLabel(deck: live.deck, count: live.windows.count, font: .system(size: 12, weight: .medium))
        }
        .contentShape(Rectangle())
    }

    /// CSS's `brightness(.85)` and `brightness(.7)`, as SwiftUI's additive brightness.
    private static let brightness: [Double] = [0, -0.12, -0.25]
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

/// A deck's dot, name and count, as the grid and the tray head both show it.
struct DeckLabel: View {
    let deck: Deck
    let count: Int
    let font: Font
    var countSuffix = ""

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(deck.color.color)
                .frame(width: 8, height: 8)
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

/// The last tile in the grid, which starts an empty deck.
struct NewDeckTile: View {
    var body: some View {
        VStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.white.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .overlay {
                    Text("+ New group")
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
