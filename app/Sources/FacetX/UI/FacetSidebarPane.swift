import SwiftUI

enum FacetSidebarStyle {
    static let width: CGFloat = 340
    static let cornerRadius: CGFloat = 12
    static let padding = EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
    static var transition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        )
    }
}

struct FacetSidebarPane<Accessory: View, Content: View>: View {
    let title: String
    let systemImage: String
    let subtitle: String?
    let closeHelp: String
    let onClose: () -> Void
    private let accessory: Accessory
    private let content: Content

    init(
        title: String,
        systemImage: String,
        subtitle: String? = nil,
        closeHelp: String = "Close sidebar",
        onClose: @escaping () -> Void,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.subtitle = subtitle
        self.closeHelp = closeHelp
        self.onClose = onClose
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            FacetSidebarHeader(
                title: title,
                systemImage: systemImage,
                subtitle: subtitle,
                closeHelp: closeHelp,
                onClose: onClose,
                accessory: { accessory }
            )

            Divider()

            content
        }
        .frame(width: FacetSidebarStyle.width)
        .frame(maxHeight: .infinity)
        .background(FacetTheme.canvas)
        .clipShape(RoundedRectangle(cornerRadius: FacetSidebarStyle.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FacetSidebarStyle.cornerRadius, style: .continuous)
                .stroke(FacetTheme.hairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
        .padding(FacetSidebarStyle.padding)
        .transition(FacetSidebarStyle.transition)
    }
}

extension FacetSidebarPane where Accessory == EmptyView {
    init(
        title: String,
        systemImage: String,
        subtitle: String? = nil,
        closeHelp: String = "Close sidebar",
        onClose: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            systemImage: systemImage,
            subtitle: subtitle,
            closeHelp: closeHelp,
            onClose: onClose,
            accessory: { EmptyView() },
            content: content
        )
    }
}

private struct FacetSidebarHeader<Accessory: View>: View {
    let title: String
    let systemImage: String
    let subtitle: String?
    let closeHelp: String
    let onClose: () -> Void
    let accessory: Accessory

    init(
        title: String,
        systemImage: String,
        subtitle: String?,
        closeHelp: String,
        onClose: @escaping () -> Void,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.systemImage = systemImage
        self.subtitle = subtitle
        self.closeHelp = closeHelp
        self.onClose = onClose
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 10) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            if let subtitle = cleanSubtitle {
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 126, alignment: .trailing)
            }

            accessory

            Button(action: onClose) {
                Image(systemName: "sidebar.trailing")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(closeHelp)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var cleanSubtitle: String? {
        guard let subtitle = subtitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !subtitle.isEmpty else {
            return nil
        }
        return subtitle
    }
}
