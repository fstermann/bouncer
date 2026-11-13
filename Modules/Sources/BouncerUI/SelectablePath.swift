import AppKit
import SwiftUI

/// A path to select and copy, cut in the middle when it does not fit. SwiftUI's selectable `Text` ran
/// past its truncation in the Settings window, over the button beside it.
struct SelectablePath: NSViewRepresentable {
    let path: String

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(labelWithString: path)
        field.isSelectable = true
        field.textColor = .secondaryLabelColor
        field.lineBreakMode = .byTruncatingMiddle
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        field.stringValue = path
        field.toolTip = path
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView field: NSTextField, context: Context) -> CGSize? {
        let natural = field.intrinsicContentSize
        return CGSize(width: min(proposal.width ?? natural.width, natural.width), height: natural.height)
    }
}
