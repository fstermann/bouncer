import Foundation

/// The Dock's auto-hide delay: how long the pointer rests at the screen edge before it shows.
public enum DockDelay {
    /// Read fresh on every call, so a delay changed with `defaults write` applies to the next reveal.
    public static var current: TimeInterval {
        let dock = "com.apple.dock" as CFString
        CFPreferencesAppSynchronize(dock)
        return seconds(from: CFPreferencesCopyAppValue("autohide-delay" as CFString, dock))
    }

    /// The delay `value` stands for: a number of seconds, or the Dock's default where none is set.
    static func seconds(from value: Any?) -> TimeInterval {
        guard let number = value as? NSNumber else { return standard }
        return max(number.doubleValue, 0)
    }

    /// What the Dock waits with no `autohide-delay` set.
    static let standard: TimeInterval = 0.5
}
