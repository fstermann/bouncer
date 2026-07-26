import BouncerFoundation
import Carbon.HIToolbox

/// Global shortcuts via Carbon's `RegisterEventHotKey`.
///
/// Chosen over a `CGEventTap` deliberately: a tap needs Accessibility permission and
/// puts our process on the path of every keystroke system-wide. `RegisterEventHotKey`
/// needs no permission and costs nothing until the exact combo fires.
@MainActor
public final class HotkeyRegistry {
    public static let shared = HotkeyRegistry()

    public struct Token: Hashable, Sendable {
        fileprivate let id: UInt32
    }

    private var actions: [UInt32: @MainActor () -> Void] = [:]
    private var hotkeys: [UInt32: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    private var nextID: UInt32 = 1

    private init() {}

    /// Returns `nil` if the system refuses the combo, usually because another app owns it.
    @discardableResult
    public func register(_ combo: KeyCombo, action: @MainActor @escaping () -> Void) -> Token? {
        installEventHandlerIfNeeded()

        let id = nextID
        nextID += 1

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(combo.keyCode),
            combo.carbonModifiers,
            EventHotKeyID(signature: Self.signature, id: id),
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            Log.hotkeys.error("RegisterEventHotKey failed for \(combo.displayString, privacy: .public): \(status)")
            return nil
        }

        hotkeys[id] = ref
        actions[id] = action
        return Token(id: id)
    }

    public func unregister(_ token: Token) {
        if let ref = hotkeys.removeValue(forKey: token.id) {
            UnregisterEventHotKey(ref)
        }
        actions[token.id] = nil
    }

    fileprivate func invoke(id: UInt32) {
        actions[id]?()
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetEventDispatcherTarget(), hotkeyEventCallback, 1, &spec, nil, &eventHandler)
    }

    nonisolated fileprivate static let signature: OSType = 0x424E_4352  // 'BNCR'
}

/// Carbon requires a bare C function pointer, so this cannot capture context.
/// Carbon dispatches hotkey events on the main thread, which makes the isolation
/// assumption below sound.
private func hotkeyEventCallback(
    _ handlerCall: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }

    var hotkeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotkeyID
    )
    guard status == noErr, hotkeyID.signature == HotkeyRegistry.signature else {
        return OSStatus(eventNotHandledErr)
    }

    MainActor.assumeIsolated {
        HotkeyRegistry.shared.invoke(id: hotkeyID.id)
    }
    return noErr
}
