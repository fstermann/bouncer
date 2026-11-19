import SwiftUI

/// Lays its views out in rows, wrapping when a row is full. Each row is centred and its views sit on
/// a common bottom edge, so cards with labels of different heights line up by their labels.
///
/// A view marked `flowRow()` takes a row of its own at full width, as the tray does under the row of
/// the deck it shows.
struct CenteredFlow: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let rows = rows(of: subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var top = bounds.minY
        for row in rows(of: subviews, width: bounds.width) {
            var left = bounds.midX - row.width / 2
            for index in row.indices {
                let size = subviews[index][FullRow.self]
                    ? CGSize(width: row.width, height: row.height) : subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: left, y: top + row.height - size.height), proposal: ProposedViewSize(size)
                )
                left += size.width + spacing
            }
            top += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(of subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            if subviews[index][FullRow.self] {
                if !row.indices.isEmpty { rows.append(row) }
                let size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
                rows.append(Row(indices: [index], width: size.width, height: size.height))
                row = Row()
                continue
            }
            let size = subviews[index].sizeThatFits(.unspecified)
            let grown = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if grown > width, !row.indices.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

/// How many of `count` items of `itemWidth`, `spacing` apart, fit in a row of `width`; at least one.
func itemsPerRow(count: Int, itemWidth: CGFloat, spacing: CGFloat, width: CGFloat) -> Int {
    max(1, min(count, Int((width + spacing) / (itemWidth + spacing))))
}

private struct FullRow: LayoutValueKey {
    static let defaultValue = false
}

extension View {
    /// Gives this view a row of its own in a `CenteredFlow`, at the flow's full width.
    func flowRow() -> some View {
        layoutValue(key: FullRow.self, value: true)
    }
}
