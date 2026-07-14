import FacetXCore
import SwiftUI

/// Presentation for the two EventKit-backed work-item kinds.
extension WorkItem.Kind {
    var color: Color {
        switch self {
        case .reminder:  return .green
        case .event: return .blue
        }
    }

    var systemImage: String {
        switch self {
        case .reminder:  return "checklist"
        case .event: return "calendar"
        }
    }

    /// Plural label, used in section headers and summary badges.
    var title: String {
        switch self {
        case .reminder:  return L10n.pick("Tasks", "任务")
        case .event: return L10n.pick("Events", "事件")
        }
    }

    /// Singular label, used in detail-pane titles and create menus.
    var singularTitle: String {
        switch self {
        case .reminder:  return L10n.pick("Task", "任务")
        case .event: return L10n.pick("Event", "事件")
        }
    }
}

/// One template for an item's row/calendar visuals so every surface (All, Plan,
/// Today) stays consistent and new code doesn't re-derive icon/color.
extension WorkItem {
    /// Tint by element type; tasks keep priority emphasis when prioritized.
    var rowTint: Color {
        if kind == .reminder, priority > 0 { return FacetTheme.priorityColor(priority) }
        return kind.color
    }

    /// Leading glyph: tasks reflect completion; others use their kind glyph.
    var rowSystemImage: String {
        kind == .reminder ? (isCompleted ? "checkmark.circle.fill" : "circle")
                          : kind.systemImage
    }
}
