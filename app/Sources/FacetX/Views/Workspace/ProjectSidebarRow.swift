import SwiftUI

// MARK: - Shared sidebar row shell

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

// MARK: - Drag preview card

/// A self-contained card rendered as the drag ghost when a sidebar row is
/// being reordered. Assign via `.draggable(_:preview:)` or render standalone.
struct SidebarDragPreview: View {
    let title: String
    let subtitle: String
    let badge: WorkspaceSidebarRow.Badge
    let tint: Color

    var body: some View {
        WorkspaceSidebarRow(title: title, subtitle: subtitle, badge: badge, tint: tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(width: 210, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(tint.opacity(0.4), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 5)
    }
}

// MARK: - Concrete rows

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

    var dragPreview: some View {
        SidebarDragPreview(
            title: project.name,
            subtitle: project.tagline.isEmpty ? project.prefix : project.tagline,
            badge: .symbol(project.appearanceIconName),
            tint: project.appearanceColor
        )
    }
}
