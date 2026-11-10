import SwiftUI

extension ClaudePage {
    /// Under the folder's name, left-aligned to it.
    func folderMenuFrame(in panel: CGRect) -> CGRect? {
        guard isChoosingFolder else { return nil }
        let maxY = panel.maxY - folderAnchor.maxY - 4
        return CGRect(origin: CGPoint(x: panel.minX + folderAnchor.minX, y: maxY - menuSize.height), size: menuSize)
    }
}

/// Keeps the page told where the folder's name is while its menu is open, and how big the menu is.
struct FolderMenuAnchoring: ViewModifier {
    let page: ClaudePage

    func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(MenuAnchor.self) { anchor in
                GeometryReader { proxy in
                    if let anchor, page.isChoosingFolder {
                        Color.clear
                            .onChange(of: proxy[anchor], initial: true) {
                                page.folderAnchor = $1
                                page.onResize?()
                            }
                    }
                }
                .allowsHitTesting(false)
            }
            .onChange(of: page.isChoosingFolder) {
                if !$1 { page.menuSize = .zero }
                page.onResize?()
            }
    }
}

/// The folders the next chat can start in, beside the panel so it can hang past its edge.
struct FolderMenu: View {
    let page: ClaudePage

    var body: some View {
        if page.isChoosingFolder {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(page.folders, id: \.self) { folder in
                    FolderChoice(folder: folder, isChosen: folder == page.folder) { page.onPickFolder?(folder) }
                }
                Divider().padding(.vertical, 4)
                FolderChoice(folder: nil, isChosen: false) { page.onChooseFolder?() }
            }
            .padding(6)
            .frame(width: 280)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.08)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.12)))
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                page.menuSize = size
                page.onResize?()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .foregroundStyle(.white)
            .environment(\.colorScheme, .dark)
        }
    }
}

/// A folder by name, with where it sits; without one, the way to the Open dialog.
private struct FolderChoice: View {
    let folder: String?
    let isChosen: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .opacity(isChosen ? 1 : 0)
                    .foregroundStyle(.secondary)
                if let folder {
                    let url = URL(filePath: folder)
                    Text(url.lastPathComponent)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    let parent = url.deletingLastPathComponent().path(percentEncoded: false)
                    Text((parent as NSString).abbreviatingWithTildeInPath)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("Choose…")
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(.white.opacity(isHovered ? 0.08 : 0), in: .rect(cornerRadius: 5))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .font(.callout)
        .onHover { isHovered = $0 }
        .help(folder ?? "Pick another folder")
    }
}
