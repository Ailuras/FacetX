import SwiftUI

struct WorkColorOption: Identifiable, Hashable {
    let id: String
    let title: String
    let color: Color
}

struct WorkIconOption: Identifiable, Hashable {
    let id: String
    let title: String
}

enum WorkAppearance {
    static let defaultColorName = "blue"
    static let defaultIconName = "folder.fill"

    static let colors: [WorkColorOption] = [
        WorkColorOption(id: "blue", title: "Blue", color: .blue),
        WorkColorOption(id: "teal", title: "Teal", color: .teal),
        WorkColorOption(id: "green", title: "Green", color: .green),
        WorkColorOption(id: "orange", title: "Orange", color: .orange),
        WorkColorOption(id: "red", title: "Red", color: .red),
        WorkColorOption(id: "pink", title: "Pink", color: .pink),
        WorkColorOption(id: "purple", title: "Purple", color: .purple),
        WorkColorOption(id: "indigo", title: "Indigo", color: .indigo)
    ]

    static let icons: [WorkIconOption] = [
        WorkIconOption(id: "folder.fill", title: "Folder"),
        WorkIconOption(id: "target", title: "Focus"),
        WorkIconOption(id: "bolt.fill", title: "Energy"),
        WorkIconOption(id: "sparkles", title: "Ideas"),
        WorkIconOption(id: "hammer.fill", title: "Build"),
        WorkIconOption(id: "paintpalette.fill", title: "Design"),
        WorkIconOption(id: "book.closed.fill", title: "Study"),
        WorkIconOption(id: "curlybraces", title: "Code"),
        WorkIconOption(id: "chart.bar.fill", title: "Metrics"),
        WorkIconOption(id: "paperplane.fill", title: "Launch"),
        WorkIconOption(id: "calendar", title: "Event"),
        WorkIconOption(id: "checklist", title: "Tasks")
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

extension Work {
    var appearanceColor: Color {
        WorkAppearance.color(for: colorName)
    }

    var appearanceIconName: String {
        WorkAppearance.iconName(for: iconName)
    }
}
