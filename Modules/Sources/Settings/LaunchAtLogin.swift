import BouncerFoundation
import ServiceManagement

/// Launch-at-login, backed by `SMAppService` rather than a stored preference — the
/// system is the source of truth, so there is no state to keep in sync.
public enum LaunchAtLogin {
    public static var isEnabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                Log.settings.error("Launch at login \(newValue, privacy: .public) failed: \(error, privacy: .public)")
            }
        }
    }
}
