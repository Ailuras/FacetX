import SwiftUI

/// A small "<count> <label>" pill used in the work and Today headers.
///
/// Optionally clickable: when `onTap` is set the chip behaves as a button with a
/// pointing-hand cursor, and `isActive` fills it in `tint` to mark the current
/// focus (used by the All view to isolate a single element type).
struct SummaryChip: View {
    let value: Int
    let label: String
    let systemImage: String
    var tint: Color? = nil
    var isActive: Bool = false
    var help: String? = nil
    var onTap: (() -> Void)? = nil

    var body: some View {
        SelectionBadge(
            text: "\(value) \(label)",
            systemImage: systemImage,
            tint: tint,
            isActive: isActive,
            help: help,
            onTap: onTap
        )
    }
}

/// A selectable mode badge with the exact metrics and interaction treatment of
/// `SummaryChip`, but without requiring a numeric value.
struct SelectionBadge: View {
    let text: String
    let systemImage: String
    var tint: Color? = nil
    var isActive: Bool = false
    var help: String? = nil
    var onTap: (() -> Void)? = nil
    @State private var isHovered = false

    var body: some View {
        if let onTap {
            Button(action: onTap) { pill }
                .buttonStyle(.plain)
                .hoverCursor(.pointingHand)
                .onHover { isHovered = $0 }
                .help(help ?? "")
        } else {
            pill
        }
    }

    private var pill: some View {
        // Mirrors FacetInfoBadge's metrics exactly so the count chips across the
        // All / Plan headers share one height and style. The explicit
        // icon+text HStack (vs a Label) also avoids the vertical icon/title flip
        // a Label does when briefly compressed during the Today panel animation.
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(isActive ? (tint ?? .secondary) : .secondary)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 8)
        .frame(height: FacetTheme.chipHeight)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(summaryFill))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .stroke(summaryStroke, lineWidth: 1))
    }

    private var summaryFill: Color {
        let color = tint ?? .accentColor
        if isActive { return color.opacity(isHovered ? 0.18 : 0.14) }
        if isHovered { return Color.primary.opacity(0.055) }
        return FacetTheme.quietPanel
    }

    private var summaryStroke: Color {
        let color = tint ?? .accentColor
        if isActive { return color.opacity(isHovered ? 0.44 : 0.34) }
        if isHovered { return color.opacity(0.24) }
        return FacetTheme.hairline
    }
}
