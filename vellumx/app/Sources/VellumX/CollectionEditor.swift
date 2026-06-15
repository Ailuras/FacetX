import SwiftUI

/// Rounded tinted folder badge shown next to each collection in the sidebar.
/// Always uses the folder glyph; color reflects the collection's label color.
struct CollectionBadge: View {
    let color: Color
    var size: CGFloat = 24
    /// When the row is selected its background is solid system-blue; a tinted
    /// colored badge washes out against it, so switch to a white glyph on a
    /// translucent-white fill — matching the selected row's text and count pill.
    var selected: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
            .fill(selected ? Color.white.opacity(0.22) : color.opacity(0.14))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "folder")
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(selected ? Color.white : color)
            )
    }
}

extension PaperCollection {
    var resolvedColor: Color { LabelColor.color(named: color) ?? .accentColor }
}
