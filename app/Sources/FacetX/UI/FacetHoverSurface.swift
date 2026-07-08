import SwiftUI

private struct FacetHoverSurfaceModifier: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    let tint: Color
    let fill: Color
    let hoverFill: Color
    let stroke: Color
    let hoverStroke: Color
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .foregroundStyle(foreground)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isHovered && isEnabled ? hoverFill : fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(isHovered && isEnabled ? hoverStroke : stroke, lineWidth: 1)
            )
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { hovering in
                isHovered = hovering && isEnabled
            }
    }

    private var foreground: Color {
        guard isEnabled else { return Color.secondary.opacity(0.45) }
        return isHovered ? tint : tint.opacity(0.82)
    }
}

extension View {
    func facetHoverSurface(tint: Color = .accentColor,
                           fill: Color = Color.primary.opacity(0.04),
                           hoverFill: Color? = nil,
                           stroke: Color = .clear,
                           hoverStroke: Color? = nil,
                           cornerRadius: CGFloat = 6) -> some View {
        modifier(FacetHoverSurfaceModifier(
            tint: tint,
            fill: fill,
            hoverFill: hoverFill ?? tint.opacity(0.12),
            stroke: stroke,
            hoverStroke: hoverStroke ?? tint.opacity(0.28),
            cornerRadius: cornerRadius
        ))
    }
}
