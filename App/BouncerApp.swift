import AppKit

/// Explicit entry point.
///
/// `@main` on an `NSApplicationDelegate` routes through `NSApplicationMain`, which
/// without a main nib brings up `NSApplication` but never attaches a delegate — the
/// app would launch and then do nothing. Wiring it by hand is both shorter and honest
/// about what happens at startup.
@main
enum BouncerApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Menu bar only: no Dock tile, no app switcher entry.
        app.setActivationPolicy(.accessory)
        app.run()
        // `NSApplication.delegate` is weak.
        withExtendedLifetime(delegate) {}
    }
}
