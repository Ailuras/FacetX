import SwiftUI

enum SidebarItem: Hashable {
    case all
    case recommended
    case pending
    case starred
    case read
    case skipped

    var displayName: String {
        switch self {
        case .all: return "All Papers"
        case .recommended: return "Recommended"
        case .pending: return "Pending"
        case .starred: return "Starred"
        case .read: return "Read"
        case .skipped: return "Skipped"
        }
    }

    var iconName: String {
        switch self {
        case .all: return "books.vertical"
        case .recommended: return "sparkles"
        case .pending: return "clock"
        case .starred: return "star"
        case .read: return "checkmark.circle"
        case .skipped: return "eye.slash"
        }
    }

    var iconColor: Color {
        switch self {
        case .all: return .primary
        case .recommended: return .orange
        case .pending: return .blue
        case .starred: return .yellow
        case .read: return .green
        case .skipped: return .secondary
        }
    }
}
