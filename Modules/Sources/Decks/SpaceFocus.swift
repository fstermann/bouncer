import AppKit

/// Brings forward a window on a Space other than the current one, which switches to that Space.
///
/// SkyLight makes the window the front one of the front process, then Accessibility raises it, which
/// moves to its Space. Both steps are needed: either alone leaves the current Space showing. The calls
/// are resolved at runtime; without them the app is activated, which goes to whichever of its windows
/// was last in front.
enum SpaceFocus {
    private typealias ProcessForPID = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
    private typealias SetFront = @convention(c) (UnsafePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError
    private typealias PostEvent = @convention(c) (UnsafePointer<ProcessSerialNumber>, UnsafePointer<UInt8>) -> CGError

    private struct Calls: @unchecked Sendable {
        let processForPID: ProcessForPID
        let setFront: SetFront
        let post: PostEvent
    }

    private static let calls: Calls? = {
        guard let sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let processForPID = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "GetProcessForPID"),
              let setFront = dlsym(sky, "_SLPSSetFrontProcessWithOptions"),
              let post = dlsym(sky, "SLPSPostEventRecordTo")
        else { return nil }
        return Calls(
            processForPID: unsafeBitCast(processForPID, to: ProcessForPID.self),
            setFront: unsafeBitCast(setFront, to: SetFront.self),
            post: unsafeBitCast(post, to: PostEvent.self)
        )
    }()

    /// Brings `window` forward and switches to its Space. Blocks on the app's replies, so never on the main actor.
    static func raise(_ window: WindowInfo) {
        guard bringForward(window), let element = WindowFocus.elementElsewhere(for: window) else {
            DispatchQueue.main.async { NSRunningApplication(processIdentifier: window.pid)?.activate() }
            return
        }
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    /// Makes `window` the front window of its app and its app the front one, which alone does not switch
    /// Spaces. Returns whether SkyLight took it.
    private static func bringForward(_ window: WindowInfo) -> Bool {
        guard let calls else { return false }
        var process = ProcessSerialNumber()
        guard calls.processForPID(window.pid, &process) == noErr else { return false }
        // 0x200: front the one window given, not every window of the app.
        guard calls.setFront(&process, window.id, 0x200) == .success else { return false }
        // A key-window event pair for the window, as the window server sends on a click in its title bar,
        // so the window takes the keyboard and not only the front place. The record is 0xF8 bytes, but newer
        // releases read past it, so the buffer is padded; the point is far off any content, so nothing is clicked.
        var record = [UInt8](repeating: 0, count: 0x100)
        record[0x04] = 0xF8
        record[0x3A] = 0x10
        var point = CGPoint(x: 300_000, y: 300_000)
        withUnsafeBytes(of: &point) { bytes in
            for (offset, byte) in bytes.enumerated() {
                record[0x10 + offset] = byte
                record[0x20 + offset] = byte
            }
        }
        withUnsafeBytes(of: window.id) { for (offset, byte) in $0.enumerated() { record[0x3C + offset] = byte } }
        record[0x08] = 0x01
        _ = calls.post(&process, record)
        record[0x08] = 0x02
        _ = calls.post(&process, record)
        return true
    }
}
