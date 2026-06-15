import SwiftUI
import AppKit

/// Shared empty / placeholder state: a soft gradient SF Symbol, a title, a
/// short message, and an optional footer (e.g. keyboard-shortcut hints). One
/// component so every empty surface — paper list, detail pane, future panels —
/// shares identical layout, sizing, and background.
struct EmptyStateView<Footer: View>: View {
    let icon: String
    let title: String
    let message: String
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.secondary.opacity(0.45), Color.accentColor.opacity(0.25)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.85))

            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            footer()

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor).opacity(0.95))
    }
}

extension EmptyStateView where Footer == EmptyView {
    init(icon: String, title: String, message: String) {
        self.init(icon: icon, title: title, message: message) { EmptyView() }
    }
}
