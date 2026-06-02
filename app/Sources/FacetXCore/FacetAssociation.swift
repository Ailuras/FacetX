import Foundation

/// Unified classification of how a raw EventKit title maps into FacetX concepts.
///
/// This is the single source of truth for deciding whether an EventKit item
/// belongs to a project and, if so, whether it is a regular item or a week goal.
/// Views should not re-parse `rawTitle` themselves.
public enum FacetAssociation {
    public enum Kind: Equatable, Sendable {
        case item(projectPrefix: String, content: String)
        case weekGoal(projectPrefix: String, title: String)
        case none
    }

    /// Classify a raw EventKit title (and optional notes) into a FacetX association.
    public static func classify(title: String, notes: String? = nil) -> Kind {
        guard let prefix = ProjectPrefix.projectName(of: title) else {
            return .none
        }
        let content = ProjectPrefix.contentBody(of: title)
        if WeekGoalEvent.isGoalContent(content) {
            return .weekGoal(projectPrefix: prefix, title: WeekGoalEvent.title(fromContent: content))
        }
        return .item(projectPrefix: prefix, content: content)
    }
}
