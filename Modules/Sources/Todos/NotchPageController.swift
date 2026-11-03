import AppKit
import Settings

/// A page of the notch panel other than the items page, as the app opens, closes and switches
/// between them.
@MainActor
public protocol NotchPageController: AnyObject {
    var isOpen: Bool { get }
    var panelFrame: CGRect? { get }
    var pages: [NotchPage] { get set }
    var onSwitchPage: (@MainActor (NotchPage) -> Void)? { get set }
    var onShortcut: (@MainActor () -> Void)? { get set }
    func open(
        on screen: NSScreen?, from start: CGRect?, closesOnLeave: Bool, onceCovered: @MainActor () async -> Void
    ) async
    func close(animated: Bool, into items: ((@escaping Shaping) async -> Void)?) async
}

extension TodoController: NotchPageController {}
extension NoteController: NotchPageController {}
extension ClaudeController: NotchPageController {}
