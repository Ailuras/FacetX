import SwiftUI

/// A small "<count> <label>" pill used in the project and Today headers.
struct SummaryChip: View {
    let value: Int
    let label: String
    let systemImage: String

    var body: some View {
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
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(FacetTheme.quietPanel))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(FacetTheme.hairline, lineWidth: 1))
    }
}
