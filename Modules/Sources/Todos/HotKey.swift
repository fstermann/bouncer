import BouncerFoundation
import Carbon.HIToolbox

/// A ⌘⇧ combination, system-wide, for as long as it exists.
///
/// A hot key registered with the system is delivered to Bouncer instead of the frontmost app, so
/// while it exists that app no longer gets the combination: Chrome's bookmarks bar toggle for ⌘⇧B,
/// a new folder in Finder for ⌘⇧N. It needs no permission, unlike watching the keyboard for it would.
@MainActor
final class HotKey {
    enum Key: UInt32 {
        case todos = 1
        case notes = 2

        var code: Int {
            switch self {
            case .todos: kVK_ANSI_B
            case .notes: kVK_ANSI_N
            }
        }

        var name: String {
            switch self {
            case .todos: "⌘⇧B"
            case .notes: "⌘⇧N"
            }
        }
    }

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let key: Key
    private let action: @MainActor () -> Void

    init?(_ key: Key, action: @MainActor @escaping () -> Void) {
        self.key = key
        self.action = action
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                let hotKey = Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue()
                var pressed = EventHotKeyID()
                let read = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &pressed
                )
                // Every hot key's handler hears every press; the others are passed on to theirs.
                guard read == noErr, pressed.signature == HotKey.signature, pressed.id == hotKey.key.rawValue else {
                    return OSStatus(eventNotHandledErr)
                }
                // Carbon delivers application events on the main thread.
                MainActor.assumeIsolated { hotKey.action() }
                return noErr
            },
            1, &pressed, Unmanaged.passUnretained(self).toOpaque(), &handler
        )
        let id = EventHotKeyID(signature: Self.signature, id: key.rawValue)
        let registered = RegisterEventHotKey(
            UInt32(key.code), UInt32(cmdKey | shiftKey), id, GetApplicationEventTarget(), 0, &hotKey
        )
        guard installed == noErr, registered == noErr else {
            Log.todos.error("""
                Registering \(key.name, privacy: .public) failed: \
                \(installed, privacy: .public) \(registered, privacy: .public)
                """)
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

    nonisolated private static let signature = OSType(0x424E_4352) // "BNCR"
}
