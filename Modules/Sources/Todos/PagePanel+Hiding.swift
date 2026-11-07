import AppKit

extension PagePanel {
    var screen: NSScreen? { window?.screen }

    /// Takes the panel off screen while `body` runs, and puts it back key, as it was.
    func hidden<T>(during body: () async -> T) async -> T {
        guard let window else { return await body() }
        window.isHiddenForScreenshot = true
        window.orderOut(nil)
        let result = await body()
        window.isHiddenForScreenshot = false
        if window === self.window {
            window.orderFrontRegardless()
            window.makeKey()
        }
        return result
    }
}
