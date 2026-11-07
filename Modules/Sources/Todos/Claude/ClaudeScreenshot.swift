import Screenshots
import SwiftUI

extension ClaudePage {
    /// Puts the screenshot's path in the question on a line of its own, which Claude Code reads the image from.
    func screenshot(_ area: ScreenshotArea) async {
        guard let onScreenshot, !isTakingScreenshot else { return }
        isTakingScreenshot = true
        defer { isTakingScreenshot = false }
        guard let path = await onScreenshot(area) else { return }
        draft = Self.draft(draft, adding: path)
        focusRequests += 1
    }

    nonisolated static func draft(_ draft: String, adding path: String) -> String {
        draft.isEmpty || draft.hasSuffix("\n") ? draft + path + "\n" : draft + "\n" + path + "\n"
    }
}

extension ClaudePageView {
    var screenshotButtons: some View {
        Group {
            Button { Task { await page.screenshot(.screen) } } label: { Image(systemName: "camera") }
                .help("Screenshot the screen into the question")
            Button { Task { await page.screenshot(.region) } } label: { Image(systemName: "camera.viewfinder") }
                .help("Screenshot a region or, after Space, a window into the question")
        }
        .buttonStyle(.plain)
        .font(.callout)
        .foregroundStyle(.secondary)
        .disabled(page.isTakingScreenshot)
    }
}
