import SwiftUI

/// A small "<count> <label>" pill used in the project and Today headers.
struct SummaryChip: View {
    let value: Int
    let label: String
    let systemImage: String

    var body: some View {
        Label("\(value) \(label)", systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(FacetTheme.quietPanel))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(FacetTheme.hairline, lineWidth: 1))
    }
}
