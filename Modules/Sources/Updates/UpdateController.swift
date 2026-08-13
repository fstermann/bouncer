import AppKit
import BouncerFoundation
import Sparkle

/// In-app updates, backed by Sparkle.
///
/// Bouncer is distributed outside the App Store and signed with a certificate Apple has not
/// issued, so nothing on the system offers the user a new version — this does.
///
/// There is no stored preference behind either toggle, the way `LaunchAtLogin` has none:
/// Sparkle writes both choices into the app's own defaults, and its documentation is explicit
/// that a parallel preference is a second source of truth waiting to disagree. The initial
/// values are the `SU*` keys in `Info.plist`.
@MainActor
public final class UpdateController {
    /// Debug builds do not update themselves. They are a different app — `com.bouncer.app.dev`
    /// — but they share this feed, so an update would replace the build you are working on with
    /// the released one, so `start()` arms nothing. Callers gate the update controls on
    /// `isRunning`, which stays false here.
    #if DEBUG
    public static let isSupported = false
    #else
    public static let isSupported = true
    #endif

    private let driver: SPUStandardUserDriver
    private let updater: SPUUpdater

    /// False until `start()` has succeeded. Sparkle drops `checkForUpdates()` on an updater that
    /// never started, with nothing shown to the user, so the controls are hidden instead.
    public private(set) var isRunning = false

    public init() {
        driver = SPUStandardUserDriver(hostBundle: .main, delegate: nil)
        updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: nil)
    }

    /// Arms Sparkle. With automatic checks on this schedules the first one; with them off it
    /// installs nothing and waits for `checkForUpdates()`.
    public func start() {
        guard Self.isSupported else {
            Log.updates.info("Dev build: no updater")
            return
        }
        do {
            try updater.start()
            isRunning = true
        } catch {
            Log.updates.error("Sparkle did not start: \(error, privacy: .public)")
        }
    }

    /// Bouncer has no Dock tile and is not the active app, so Sparkle's window would open
    /// behind whatever the user is looking at.
    public func checkForUpdates() {
        guard isRunning else { return }
        NSApp.activate(ignoringOtherApps: true)
        updater.checkForUpdates()
    }

    /// Set only when the user changes the setting — assigning on every launch would reset
    /// Sparkle's schedule each time.
    public var automaticallyChecks: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }

    /// Only meaningful while `automaticallyChecks` is on: Sparkle derives this from it, and reads
    /// NO — and ignores a write — whenever checks are off. Read it again after every write to
    /// `automaticallyChecks`, never cache it across one.
    public var automaticallyDownloads: Bool {
        get { updater.automaticallyDownloadsUpdates }
        set { updater.automaticallyDownloadsUpdates = newValue }
    }

    /// What to show next to the update controls.
    public static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}
