import SwiftUI

/// What a `PagePanel` shows: a page that measures its own height, and may hang a menu past the
/// panel's edge.
@MainActor
protocol PanelPage: AnyObject {
    associatedtype Content: View
    associatedtype Menu: View
    var width: CGFloat { get }
    var height: CGFloat { get }
    /// The row beside the notch, which the page starts below.
    var menuBarHeight: CGFloat { get set }
    /// Bumped each time the panel opens, to put the cursor in the page's field.
    var focusRequests: Int { get set }
    /// Where the open menu hangs, in screen coordinates, under the panel resting at `panel`.
    func menuFrame(in panel: CGRect) -> CGRect?
    var view: Content { get }
    var menuView: Menu { get }
}
