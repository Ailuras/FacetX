import FacetXCore
import SwiftUI

/// Presentation for the four FacetX element types — the single source of truth
/// for each kind's color, SF Symbol, and localized label across the sidebar,
/// All-view sections, summary badges, and timeline.
extension FacetKind {
    var color: Color {
        switch self {
        case .task:  return .green
        case .event: return .blue
        case .paper: return .red
        case .note:  return .yellow
        }
    }

    var systemImage: String {
        switch self {
        case .task:  return "checklist"
        case .event: return "calendar"
        case .paper: return "books.vertical"
        case .note:  return "note.text"
        }
    }

    /// Plural label, used in section headers and summary badges.
    var title: String {
        switch self {
        case .task:  return L10n.pick("Tasks", "任务")
        case .event: return L10n.pick("Events", "事件")
        case .paper: return L10n.pick("Paper", "文献")
        case .note:  return L10n.pick("Notes", "笔记")
        }
    }

    /// Singular label, used in detail-pane titles and create menus.
    var singularTitle: String {
        switch self {
        case .task:  return L10n.pick("Task", "任务")
        case .event: return L10n.pick("Event", "事件")
        case .paper: return L10n.pick("Paper", "文献")
        case .note:  return L10n.pick("Note", "笔记")
        }
    }
}

/// One template for an item's row/calendar visuals so every surface (All, Plan,
/// Today) stays consistent and new code doesn't re-derive icon/color.
extension ProjectItem {
    /// Tint by element type; tasks keep priority emphasis when prioritized.
    var rowTint: Color {
        if facetKind == .task, priority > 0 { return FacetTheme.priorityColor(priority) }
        return facetKind.color
    }

    /// Leading glyph: tasks reflect completion; others use their kind glyph.
    var rowSystemImage: String {
        facetKind == .task ? (isCompleted ? "checkmark.circle.fill" : "circle")
                           : facetKind.systemImage
    }
}
