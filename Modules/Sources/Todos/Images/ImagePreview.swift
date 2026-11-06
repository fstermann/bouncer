import AppKit
import SwiftUI

/// An embedded image's icon, which shows the image whole under the pointer while the pointer rests on it.
struct ImagePreview: View {
    let name: String
    let images: PastedImages
    @State private var hovering: Task<Void, Never>?

    private static let delay: Duration = .milliseconds(300)

    var body: some View {
        Image(systemName: "photo")
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
            .onHover(perform: hover)
            .onDisappear {
                hovering?.cancel()
                ImagePopover.shared.hide()
            }
    }

    private func hover(_ isInside: Bool) {
        hovering?.cancel()
        ImagePopover.shared.hide()
        guard isInside else { return }
        hovering = Task {
            try? await Task.sleep(for: Self.delay)
            guard !Task.isCancelled, let image = images.load(name) else { return }
            ImagePopover.shared.show(image, under: NSEvent.mouseLocation)
        }
    }
}

/// The image shown whole, in a window of its own over the panels. It takes no clicks and never
/// becomes key, so it neither closes the panel under it nor ends the hover that opened it.
@MainActor
final class ImagePopover {
    static let shared = ImagePopover()
    private var window: NSPanel?

    private static let largest = CGSize(width: 420, height: 320)
    private static let gap: CGFloat = 16
    private static let padding: CGFloat = 6

    func show(_ image: NSImage, under pointer: CGPoint) {
        let fitted = Self.fitted(image.size)
        let size = CGSize(width: fitted.width + 2 * Self.padding, height: fitted.height + 2 * Self.padding)
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) }?.frame ?? .zero
        let left = min(max(pointer.x - size.width / 2, screen.minX), screen.maxX - size.width)
        // Under the pointer, or over it where there is no room below.
        let below = pointer.y - Self.gap - size.height
        let bottom = below >= screen.minY ? below : pointer.y + Self.gap
        let frame = CGRect(x: left.rounded(), y: bottom.rounded(), width: size.width, height: size.height)
        let window = window ?? Self.makeWindow()
        self.window = window
        window.contentView = NSHostingView(rootView: Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: fitted.width, height: fitted.height)
            .padding(Self.padding)
            .background(RoundedRectangle(cornerRadius: 8).fill(.black))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.15))))
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }

    static func fitted(_ size: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        let scale = min(1, largest.width / size.width, largest.height / size.height)
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }

    private static func makeWindow() -> NSPanel {
        let window = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        // Over the pages' panel.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 5)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        return window
    }
}
