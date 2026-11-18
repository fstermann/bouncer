import AppKit
import ApplicationServices

/// Brings other apps' windows forward through Accessibility, the only public way to raise one
/// particular window of another app.
///
/// A window server window and its accessibility element share no public identifier. The private
/// `_AXUIElementGetWindow` reads the one from the other; it is resolved at runtime, so a release that
/// drops it falls back to matching frame and title rather than crashing.
enum WindowFocus {
    private typealias GetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    private static let getWindow: GetWindow? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else {
            return nil
        }
        return unsafeBitCast(symbol, to: GetWindow.self)
    }()

    /// Makes `windows` the frontmost, the last of them focused, and its app active.
    ///
    /// Accessibility calls block, so this is never called from the main actor.
    static func raise(_ windows: [WindowInfo]) {
        guard let focused = windows.last else { return }
        let elements = windows.map { ($0, element(for: $0)) }
        for (_, element) in elements {
            if let element { AXUIElementPerformAction(element, kAXRaiseAction as CFString) }
        }
        let app = AXUIElementCreateApplication(focused.pid)
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        if let element = elements.last?.1 {
            AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        }
    }

    private typealias RemoteElement = @convention(c) (CFData) -> Unmanaged<AXUIElement>?

    private static let remoteElement: RemoteElement? = {
        dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementCreateWithRemoteToken")
            .map { unsafeBitCast($0, to: RemoteElement.self) }
    }()

    /// The accessibility element of a window on another Space, which the app leaves out of its window list.
    ///
    /// An element is named by its app and a number; the private `_AXUIElementCreateWithRemoteToken`
    /// makes one from those. The numbers are tried from 0 until one is `window`, or `budget` runs out:
    /// one round trip to the app each, so this never runs on the main actor.
    static func elementElsewhere(for window: WindowInfo, budget: Duration = .milliseconds(250)) -> AXUIElement? {
        guard let remoteElement, let getWindow else { return nil }
        // The token: the pid, 4 zero bytes, "coco", then the element's number, all in native byte order.
        var token = [UInt8](repeating: 0, count: 20)
        withUnsafeBytes(of: window.pid) { for (offset, byte) in $0.enumerated() { token[offset] = byte } }
        withUnsafeBytes(of: Int32(0x636F_636F)) { for (offset, byte) in $0.enumerated() { token[8 + offset] = byte } }
        let clock = ContinuousClock()
        let deadline = clock.now + budget
        var number: UInt64 = 0
        while clock.now < deadline {
            withUnsafeBytes(of: number) { for (offset, byte) in $0.enumerated() { token[12 + offset] = byte } }
            number += 1
            guard let element = remoteElement(Data(token) as CFData)?.takeRetainedValue() else { continue }
            var id: CGWindowID = 0
            guard getWindow(element, &id) == .success, id == window.id else { continue }
            // Every element inside a window reports that window's number; only the window itself is the one.
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
            if role as? String == kAXWindowRole { return element }
        }
        return nil
    }

    /// The accessibility element of `window`: by window number, or else by frame and title.
    static func element(for window: WindowInfo) -> AXUIElement? {
        let app = AXUIElementCreateApplication(window.pid)
        // An app that has stopped answering must not hold the overlay's click up for long.
        AXUIElementSetMessagingTimeout(app, 1)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let elements = value as? [AXUIElement]
        else { return nil }
        if let getWindow {
            let match = elements.first { element in
                var id: CGWindowID = 0
                return getWindow(element, &id) == .success && id == window.id
            }
            if let match { return match }
        }
        return elements.first { frame(of: $0) == window.frame && title(of: $0) == window.title }
            ?? elements.first { frame(of: $0) == window.frame }
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size,
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        // Downcast only after the type ID checks: a plain cast between CF types is unchecked.
        guard AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &origin),
              AXValueGetValue(unsafeDowncast(size, to: AXValue.self), .cgSize, &extent)
        else { return nil }
        return CGRect(origin: origin, size: extent)
    }

    private static func title(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }
}
