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
