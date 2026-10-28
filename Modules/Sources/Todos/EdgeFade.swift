import SwiftUI

/// A mask for a scroll view that fades out the ends its content runs on past, the further the more,
/// so the fade does not appear all at once.
struct EdgeFade: View {
    private static let length: CGFloat = 24
    let axis: Axis
    /// How far the content runs on past each end.
    let beforeStart: CGFloat
    let pastEnd: CGFloat
    /// How far the content runs on before its fade is full: no further than the space before the
    /// content's first line, which would otherwise reach the edge half faded.
    var ramp: CGFloat = length

    var body: some View {
        let stack = axis == .horizontal
            ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
        stack {
            edge(fading: beforeStart, toward: axis == .horizontal ? .leading : .top)
            Color.black
            edge(fading: pastEnd, toward: axis == .horizontal ? .trailing : .bottom)
        }
    }

    private func edge(fading overflow: CGFloat, toward end: UnitPoint) -> some View {
        LinearGradient(
            colors: [.black, .black.opacity(1 - min(max(overflow, 0) / ramp, 1))],
            startPoint: UnitPoint(x: 1 - end.x, y: 1 - end.y), endPoint: end
        )
        .frame(width: axis == .horizontal ? Self.length : nil, height: axis == .vertical ? Self.length : nil)
    }
}
