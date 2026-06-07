import SwiftUI

/// Wraps subviews onto multiple rows when the proposed width is exceeded.
/// Used for tag chip clouds in the sidebar.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6
    var alignment: HorizontalAlignment = .leading

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = layout(subviews: subviews, maxWidth: maxWidth)
        let height = rows.reduce(0) { $0 + $1.height } + max(0, CGFloat(rows.count - 1)) * lineSpacing
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: maxWidth.isFinite ? maxWidth : width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = layout(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for entry in row.items {
                entry.subview.place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(width: entry.size.width, height: entry.size.height)
                )
                x += entry.size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        struct Entry { let subview: LayoutSubview; let size: CGSize }
        var items: [Entry] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func layout(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            let prospectiveWidth = rows[rows.count - 1].items.isEmpty
                ? size.width
                : rows[rows.count - 1].width + spacing + size.width
            if prospectiveWidth > maxWidth, !rows[rows.count - 1].items.isEmpty {
                rows.append(Row())
            }
            var current = rows.removeLast()
            if !current.items.isEmpty { current.width += spacing }
            current.items.append(.init(subview: sv, size: size))
            current.width += size.width
            current.height = max(current.height, size.height)
            rows.append(current)
        }
        return rows
    }
}
