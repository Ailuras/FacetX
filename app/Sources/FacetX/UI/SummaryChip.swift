import SwiftUI

/// A small "<count> <label>" pill used in the project and Today headers.
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
    var onTap: (() -> Void)? = nil

    var body: some View {
        if let onTap {
            Button(action: onTap) { pill }
                .buttonStyle(.plain)
                .hoverCursor(.pointingHand)
        } else {
            pill
        }
    }

    private var pill: some View {
        // Mirrors FacetInfoBadge's metrics exactly so the count chips across the
        // All / Week / Month headers share one height and style. The explicit
        // icon+text HStack (vs a Label) also avoids the vertical icon/title flip
        // a Label does when briefly compressed during the Today panel animation.
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 10))
            Text("\(value) \(label)")
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(isActive ? (tint ?? .secondary) : .secondary)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 8)
        .frame(height: FacetTheme.chipHeight)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(isActive ? (tint ?? .accentColor).opacity(0.14) : FacetTheme.quietPanel))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .stroke(isActive ? (tint ?? .accentColor).opacity(0.34) : FacetTheme.hairline, lineWidth: 1))
    }
}
