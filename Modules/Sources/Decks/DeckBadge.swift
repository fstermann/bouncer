import AppKit
import Settings
import SwiftUI

/// The SF Symbols a deck's badge can show.
enum DeckSymbols {
    /// What a deck shows until one is picked.
    static let fallback = "rectangle.stack.fill"

    static let choices = [
        fallback, "star.fill", "heart.fill", "bolt.fill", "flame.fill", "leaf.fill",
        "house.fill", "briefcase.fill", "person.2.fill", "bubble.left.and.bubble.right.fill", "envelope.fill",
        "calendar", "book.fill", "graduationcap.fill", "hammer.fill", "wrench.and.screwdriver.fill",
        "gearshape.fill", "terminal.fill", "chevron.left.forwardslash.chevron.right", "sparkles",
        "paintbrush.fill", "music.note", "gamecontroller.fill", "cart.fill"
    ]

    static func symbol(of deck: Deck) -> String {
        deck.symbol ?? fallback
    }
}

/// One window for each app among `windows`, in the order the apps first appear, for the app row.
enum DeckApps {
    static func distinct(_ windows: [WindowInfo]) -> [WindowInfo] {
        var seen: Set<String> = []
        return windows.filter { seen.insert(DeckMatching.app(of: $0)).inserted }
    }
}

/// A deck's symbol on a dark glass circle: on the corner of its stack, and before its name in the tray.
struct DeckBadge: View {
    let deck: Deck
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: DeckSymbols.symbol(of: deck))
            .font(.system(size: size * 0.43, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color(white: 0.1).opacity(0.85), in: Circle())
            .overlay { Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.5) }
            .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
    }
}

/// The icons of the apps in a deck, overlapping, the last place taken by "+N" past `limit`.
struct AppIconRow: View {
    let windows: [WindowInfo]
    let overview: Overview
    var limit = 4

    var body: some View {
        let apps = DeckApps.distinct(windows)
        let shown = apps.count > limit ? Array(apps.prefix(limit - 1)) : apps
        HStack(spacing: -4) {
            ForEach(shown, id: \.id) { window in
                Image(nsImage: overview.icon(of: window))
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            if apps.count > shown.count {
                Text("+\(apps.count - shown.count)")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 16, height: 16)
                    .background(.black.opacity(0.6), in: Circle())
                    .padding(.leading, 6)
            }
        }
    }
}

/// A row of every symbol a deck can take, the deck's own ringed, under its name while it is renamed.
struct SymbolPicker: View {
    let deck: Deck
    let overview: Overview

    var body: some View {
        HStack(spacing: 6) {
            ForEach(DeckSymbols.choices, id: \.self) { symbol in
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(.white.opacity(0.12), in: Circle())
                    .overlay {
                        Circle().strokeBorder(.white, lineWidth: symbol == DeckSymbols.symbol(of: deck) ? 2 : 0)
                    }
                    .contentShape(Circle())
                    .onTapGesture { overview.setSymbol(deck.id, to: symbol) }
            }
        }
    }
}

/// A window's app icon, then its name, under its picture; a desktop, which has no app, shows its name only.
struct WindowName: View {
    let label: String
    let icon: NSImage?

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            Text(label)
                .truncationMode(.tail)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.4), radius: 1.5, y: 1)
        .lineLimit(1)
    }
}
