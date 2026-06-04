import SwiftUI

struct ProjectEditorHeader: View {
    let title: String
    let subtitle: String
    let initial: String
    let tint: Color
    let systemImage: String?

    init(title: String, subtitle: String, initial: String,
         tint: Color = Color.accentColor, systemImage: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.initial = initial
        self.tint = tint
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(tint.opacity(0.14))
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(tint)
                } else {
                    Text(initial)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(tint)
                }
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

struct ProjectEditorAppearancePicker: View {
    @Binding var colorName: String
    @Binding var iconName: String
    let initial: String

    private var selectedColor: Color {
        ProjectAppearance.color(for: colorName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                projectPreview

                VStack(alignment: .leading, spacing: 4) {
                    Text("Badge")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Divider().opacity(0.42)

            VStack(alignment: .leading, spacing: 8) {
                Text("Color")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(ProjectAppearance.colors) { option in
                        Button {
                            colorName = option.id
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(option.color)
                                if colorName == option.id {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(Color.white)
                                }
                            }
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle()
                                    .stroke(Color.primary.opacity(colorName == option.id ? 0.18 : 0.08),
                                            lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .help(option.title)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Icon")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: iconColumns, alignment: .leading, spacing: 7) {
                    ForEach(ProjectAppearance.icons) { option in
                        Button {
                            iconName = option.id
                        } label: {
                            Image(systemName: option.id)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(iconName == option.id ? selectedColor : .secondary)
                                .frame(width: 30, height: 26)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(iconName == option.id ? selectedColor.opacity(0.14) : FacetTheme.panel.opacity(0.58))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(iconName == option.id ? selectedColor.opacity(0.34) : FacetTheme.hairline,
                                                lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(option.title)
                    }
                }
            }
        }
    }

    private var projectPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(selectedColor.opacity(0.14))
            Image(systemName: ProjectAppearance.iconName(for: iconName))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(selectedColor)
        }
        .frame(width: 38, height: 38)
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(FacetTheme.hairline, lineWidth: 1)
        )
        .accessibilityLabel(initial)
    }

    private var iconColumns: [GridItem] {
        Array(repeating: GridItem(.fixed(30), spacing: 7), count: 6)
    }
}

struct ProjectEditorCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.86))
            content
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

struct ProjectEditorTextField: View {
    let title: String
    @Binding var text: String
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(FacetTheme.panel.opacity(0.70))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(FacetTheme.hairline, lineWidth: 1)
                )
        }
    }
}

struct ProjectEditorPicker: View {
    let title: String
    @Binding var selection: String
    let options: [String]

    private let pickerWidth: CGFloat = 230

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()

            Menu {
                if options.isEmpty {
                    Button("None") { selection = "" }
                } else {
                    ForEach(options, id: \.self) { option in
                        Button(option) { selection = option }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(selection.isEmpty ? "None" : selection)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(selection.isEmpty ? .secondary : .primary)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 9)
                .frame(width: pickerWidth, height: 24)
                .background(FacetTheme.panel.opacity(0.70))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
        }
    }
}

struct ProjectEditorHelp: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}

struct ProjectEditorWarning: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.caption2)
            .foregroundStyle(.orange)
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
