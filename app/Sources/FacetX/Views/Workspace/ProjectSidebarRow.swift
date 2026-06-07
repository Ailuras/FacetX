import SwiftUI

struct WorkspaceSidebarRow: View {
    enum Badge {
        case text(String)
        case symbol(String)
    }

    let title: String
    let subtitle: String
    let badge: Badge
    let tint: Color

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tint.opacity(0.14))

                badgeView
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder private var badgeView: some View {
        switch badge {
        case .text(let value):
            Text(value)
        case .symbol(let name):
            Image(systemName: name)
        }
    }
}

struct TagSidebarRow: View {
    let tag: String
    let count: Int
    let color: Color
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(isSelected ? color : color.opacity(0.30))
                    .frame(width: 10, height: 10)
            }
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(tag)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                Text("\(count) items")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 3)
    }
}

struct ProjectSidebarRow: View {
    let project: Project

    var body: some View {
        WorkspaceSidebarRow(
            title: project.name,
            subtitle: project.tagline.isEmpty ? project.prefix : project.tagline,
            badge: .symbol(project.appearanceIconName),
            tint: project.appearanceColor
        )
    }
}
