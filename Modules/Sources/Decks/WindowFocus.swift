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
