import SwiftUI

struct FacetSidebarContent<Content: View>: View {
    var spacing: CGFloat = 14
    var verticalPadding: CGFloat = 16
    private let content: Content

    init(
        spacing: CGFloat = 14,
        verticalPadding: CGFloat = 16,
        @ViewBuilder content: () -> Content
    ) {
        self.spacing = spacing
        self.verticalPadding = verticalPadding
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, FacetSidebarStyle.contentInset)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, alignment: .top)
            .hideScrollIndicators()
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity)
    }
}

struct FacetDetailSection<Content: View>: View {
    let title: String
    let systemImage: String
    private let content: Content

    init(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)

            FacetDetailBox {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FacetDetailBox<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FacetTheme.quietPanel)
            .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                    .stroke(FacetTheme.hairline, lineWidth: 1)
            )
    }
}

/// One resource family inside a detail card. Documents, literature and commits
/// share this exact header, count badge, empty state and row spacing.
struct FacetResourceGroup<Action: View, Content: View>: View {
    let title: String
    let count: Int
    let systemImage: String
    let tint: Color
    let emptyText: String
    private let action: Action
    private let content: Content

    init(
        title: String,
        count: Int,
        systemImage: String,
        tint: Color,
        emptyText: String,
        @ViewBuilder action: () -> Action,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.count = count
        self.systemImage = systemImage
        self.tint = tint
        self.emptyText = emptyText
        self.action = action()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 24, height: 24)
                    .background(tint.opacity(0.11))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                Text(title)
                    .font(.system(size: 11, weight: .semibold))

                Text("\(count)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(Color.secondary.opacity(0.10))
                    .clipShape(Capsule())

                Spacer(minLength: 8)
                action
            }

            if count == 0 {
                FacetDetailEmptyRow(text: emptyText, systemImage: systemImage)
            } else {
                VStack(spacing: 6) {
                    content
                }
            }
        }
        .padding(10)
    }
}

struct FacetDetailResourceRow<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let tint: Color
    var titleDesign: Font.Design = .default
    private let trailing: Trailing

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        tint: Color,
        titleDesign: Font.Design = .default,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.titleDesign = titleDesign
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.11))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .medium, design: titleDesign))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.028))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(FacetTheme.hairline, lineWidth: 1)
        )
    }
}

struct FacetDetailEmptyRow: View {
    let text: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 10))
                .frame(width: 18)
            Text(text)
                .font(.system(size: 10.5))
            Spacer(minLength: 0)
        }
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 9)
        .frame(minHeight: 30)
        .background(Color.primary.opacity(0.018))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct FacetDetailMetadataRow: View {
    let label: String
    let value: String
    var monospaced = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .fontDesign(monospaced ? .monospaced : .default)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.system(size: 10.5))
        .padding(.horizontal, 10)
        .frame(minHeight: 30)
    }
}

struct FacetDetailRowAction: View {
    let systemImage: String
    let help: String
    var tint: Color = .secondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 9.5, weight: .semibold))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
                .facetHoverSurface(
                    tint: tint,
                    fill: Color.clear,
                    hoverFill: tint.opacity(0.10),
                    hoverStroke: tint.opacity(0.24)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
