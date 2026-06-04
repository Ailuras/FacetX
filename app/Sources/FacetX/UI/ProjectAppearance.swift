import SwiftUI

struct ProjectColorOption: Identifiable, Hashable {
    let id: String
    let title: String
    let color: Color
}

struct ProjectIconOption: Identifiable, Hashable {
    let id: String
    let title: String
}

enum ProjectAppearance {
    static let defaultColorName = "blue"
    static let defaultIconName = "folder.fill"

    static let colors: [ProjectColorOption] = [
        ProjectColorOption(id: "blue", title: "Blue", color: .blue),
        ProjectColorOption(id: "teal", title: "Teal", color: .teal),
        ProjectColorOption(id: "green", title: "Green", color: .green),
        ProjectColorOption(id: "orange", title: "Orange", color: .orange),
        ProjectColorOption(id: "red", title: "Red", color: .red),
        ProjectColorOption(id: "pink", title: "Pink", color: .pink),
        ProjectColorOption(id: "purple", title: "Purple", color: .purple),
        ProjectColorOption(id: "indigo", title: "Indigo", color: .indigo)
    ]

    static let icons: [ProjectIconOption] = [
        ProjectIconOption(id: "folder.fill", title: "Folder"),
        ProjectIconOption(id: "target", title: "Focus"),
        ProjectIconOption(id: "bolt.fill", title: "Energy"),
        ProjectIconOption(id: "sparkles", title: "Ideas"),
        ProjectIconOption(id: "hammer.fill", title: "Build"),
        ProjectIconOption(id: "paintpalette.fill", title: "Design"),
        ProjectIconOption(id: "book.closed.fill", title: "Study"),
        ProjectIconOption(id: "curlybraces", title: "Code"),
        ProjectIconOption(id: "chart.bar.fill", title: "Metrics"),
        ProjectIconOption(id: "paperplane.fill", title: "Launch"),
        ProjectIconOption(id: "calendar", title: "Schedule"),
        ProjectIconOption(id: "checklist", title: "Tasks")
    ]

    static func color(for name: String?) -> Color {
        guard let name,
              let option = colors.first(where: { $0.id == name }) else {
            return Color.accentColor
        }
        return option.color
    }

    static func iconName(for name: String?) -> String {
        guard let name,
              icons.contains(where: { $0.id == name }) else {
            return defaultIconName
        }
        return name
    }
}

extension Project {
    var appearanceColor: Color {
        ProjectAppearance.color(for: colorName)
    }

    var appearanceIconName: String {
        ProjectAppearance.iconName(for: iconName)
    }
}
