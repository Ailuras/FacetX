import SwiftUI

enum SettingsUI {
    static let sectionFont = Font.system(size: 13, weight: .semibold)
    static let rowFont = Font.system(size: 13, weight: .medium)
    static let secondaryFont = Font.system(size: 12)
    static let smallFont = Font.system(size: 11)
    static let controlWidth: CGFloat = 230
}

struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let warning: String?
    let content: () -> Content

    init(title: String, subtitle: String, systemImage: String, warning: String?,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.warning = warning
        self.content = content
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let warning {
                    persistenceWarningView(warning)
                }
                content()
            }
            .padding(20)
        }
        .background(FacetTheme.canvas)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.13))
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                Text(subtitle)
                    .font(SettingsUI.secondaryFont)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private func persistenceWarningView(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(SettingsUI.secondaryFont)
            .foregroundStyle(.orange)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                    .stroke(Color.orange.opacity(0.24), lineWidth: 1)
            )
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    let systemImage: String
    let subtitle: String?
    let content: () -> Content

    init(title: String, systemImage: String, subtitle: String? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.subtitle = subtitle
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Label(title, systemImage: systemImage)
                    .font(SettingsUI.sectionFont)
                    .foregroundStyle(.primary.opacity(0.86))
                if let subtitle {
                    Text(subtitle)
                        .font(SettingsUI.smallFont)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 26)
                }
            }

            content()
        }
        .padding(14)
        .background(FacetTheme.quietPanel)
        .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                .stroke(FacetTheme.hairline, lineWidth: 1)
        )
    }
}

struct SettingsRow<Content: View>: View {
    let title: String
    let systemImage: String
    var subtitle: String? = nil
    let content: () -> Content

    init(title: String, systemImage: String, subtitle: String? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.subtitle = subtitle
        self.content = content
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(SettingsUI.rowFont)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            content()
        }
        .padding(.vertical, 3)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider()
            .opacity(0.42)
            .padding(.leading, 28)
    }
}

struct SummaryPill: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 20, height: 20)
                .background(Color.accentColor.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(SettingsUI.smallFont)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(FacetTheme.quietPanel)
        .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                .stroke(FacetTheme.hairline, lineWidth: 1)
        )
    }
}
