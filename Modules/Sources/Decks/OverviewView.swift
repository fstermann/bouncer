import SwiftUI

/// The overview's content: the dimmed, blurred desktop, a hint, and a card for every window.
struct OverviewView: View {
    let overview: Overview

    var body: some View {
        ZStack(alignment: .top) {
            backdrop
                .contentShape(Rectangle())
                .onTapGesture { overview.onDismiss?() }
            VStack(spacing: 18) {
                hint
                if !overview.canRaise || !overview.canSeeTitles { PermissionBanner(overview: overview) }
                CenteredFlow(spacing: Metrics.gap, lineSpacing: Metrics.gap) {
                    ForEach(overview.windows) { window in
                        WindowCard(
                            window: window, icon: overview.icon(of: window), picture: overview.thumbnails[window.id]
                        ) { overview.onPick?([window]) }
                    }
                }
                .padding(.horizontal, 30)
            }
            .padding(.top, 28)
        }
        .ignoresSafeArea()
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
        Text("Click a window to focus it  ·  esc to close")
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
    let icon: NSImage
    let picture: NSImage?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 9) {
            WindowThumbnail(icon: icon, picture: picture)
                .frame(width: Metrics.card.width, height: Metrics.card.height)
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.cornerRadius + 2)
                        .inset(by: -3.5)
                        .stroke(Metrics.highlight, lineWidth: 3)
                        .opacity(isHovered ? 1 : 0)
                }
            Text(window.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 1.5, y: 1)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: Metrics.card.width)
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(perform: action)
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
                        .transition(.opacity)
                } else {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 48, height: 48)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius))
            .animation(.easeOut(duration: 0.2), value: picture != nil)
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
