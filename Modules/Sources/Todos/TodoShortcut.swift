import BouncerFoundation
import Carbon.HIToolbox

/// ⌘⇧B, system-wide, for as long as it exists.
///
/// A hot key registered with the system is delivered to Bouncer instead of the frontmost app, so
/// while it exists that app no longer gets the combination: Chrome's bookmarks bar toggle among
/// them. It needs no permission, unlike watching the keyboard for it would.
@MainActor
final class TodoShortcut {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: @MainActor () -> Void

    init?(action: @MainActor @escaping () -> Void) {
        self.action = action
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, context in
                guard let context else { return OSStatus(eventNotHandledErr) }
                let shortcut = Unmanaged<TodoShortcut>.fromOpaque(context).takeUnretainedValue()
                // Carbon delivers application events on the main thread.
                MainActor.assumeIsolated { shortcut.action() }
                return noErr
            },
            1, &pressed, Unmanaged.passUnretained(self).toOpaque(), &handler
        )
        let id = EventHotKeyID(signature: OSType(0x424E_4352), id: 1) // "BNCR"
        let registered = RegisterEventHotKey(
            UInt32(kVK_ANSI_B), UInt32(cmdKey | shiftKey), id, GetApplicationEventTarget(), 0, &hotKey
        )
        guard installed == noErr, registered == noErr else {
            Log.todos.error("Registering ⌘⇧B failed: \(installed, privacy: .public) \(registered, privacy: .public)")
            unregister()
            return nil
        }
    }

    /// Hands the combination back to the apps.
    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
    }
}
