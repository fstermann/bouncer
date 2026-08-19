import Foundation

/// How this copy of Bouncer was installed, which decides who owns updates.
///
/// The Homebrew cask writes `InstalledViaHomebrew` into the app's defaults from its `postflight`;
/// a direct download never does. Unlike the update toggles — which the `UpdateController` keeps
/// out of our defaults because they mirror Sparkle's live state — this is a fact fixed at install
/// time, so our own key is the source of truth, not a copy of one.
public enum InstallChannel: Sendable, Equatable {
    /// A downloaded DMG. Sparkle owns updates.
    case direct
    /// Installed by a Homebrew cask. `brew upgrade` owns updates; Sparkle stays off.
    case homebrew

    static let homebrewKey = "InstalledViaHomebrew"

    public static func current(defaults: UserDefaults = .standard) -> InstallChannel {
        defaults.bool(forKey: homebrewKey) ? .homebrew : .direct
    }
}
