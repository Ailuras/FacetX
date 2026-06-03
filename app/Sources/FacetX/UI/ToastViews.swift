import SwiftUI

/// A single toast notification card.
struct ToastView: View {
    let toast: Toast
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.type.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(toast.type.color)
                .frame(width: 20, height: 20)

            Text(toast.message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            if let action = toast.action {
                Button(action.title) {
                    action.handler()
                    onDismiss()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .font(.system(size: 12, weight: .semibold))
            }

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minWidth: 260, maxWidth: 340, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                .fill(FacetTheme.panel.opacity(0.92))
                .background(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                .stroke(FacetTheme.hairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 6)
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        ))
    }
}

/// Stacks toast cards vertically in the top-trailing corner.
struct ToastStack: View {
    @EnvironmentObject private var toast: ToastController

    var body: some View {
        VStack(spacing: 10) {
            ForEach(toast.toasts) { t in
                ToastView(toast: t) {
                    toast.dismiss(t.id)
                }
            }
        }
        .padding(.top, 16)
        .padding(.trailing, 16)
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: toast.toasts.map(\.id))
    }
}

/// A persistent banner shown at the top of the window.
struct BannerView: View {
    let banner: Banner
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: banner.type.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(banner.type.foregroundColor)

            Text(banner.message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)

            Spacer(minLength: 8)

            if let action = banner.action {
                Button(action.title) {
                    action.handler()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .font(.system(size: 12, weight: .semibold))
            }

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(banner.type.backgroundColor)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(banner.type.foregroundColor.opacity(0.20)),
            alignment: .bottom
        )
        .transition(.asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .move(edge: .top).combined(with: .opacity)
        ))
    }
}
