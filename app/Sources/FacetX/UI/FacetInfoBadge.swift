import SwiftUI

struct FacetInfoBadge: View {
    let text: String
    let systemImage: String
    var tint: Color = .secondary
    var fill: Color = FacetTheme.quietPanel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(FacetTheme.hairline, lineWidth: 1)
        )
    }
}
