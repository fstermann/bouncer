import SwiftUI

/// The frosted panel under the grid that shows one deck's windows at a larger size.
struct DeckTray: View {
    let live: LiveDeck
    let overview: Overview
    let width: CGFloat

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                DeckLabel(
                    deck: live.deck, count: live.windows.count, font: .system(size: 15, weight: .semibold),
                    countSuffix: live.windows.count == 1 ? " window" : " windows"
                )
                Spacer()
                HStack(spacing: 8) {
                    TrayButton(title: "Tile all") {}
                    TrayButton(title: "Rename") {}
                    TrayButton(title: "Ungroup") {}
                }
            }
            HStack(alignment: .top, spacing: width * 0.025) {
                ForEach(Array(live.windows.enumerated()), id: \.element.id) { index, window in
                    TrayCard(window: window, overview: overview, index: index)
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
