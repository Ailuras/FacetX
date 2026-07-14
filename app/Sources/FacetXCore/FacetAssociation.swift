import Foundation

/// Unified classification of how a raw EventKit title maps into FacetX concepts.
///
/// This is the single source of truth for deciding whether an EventKit item
/// belongs to a work and, if so, whether it is a regular item or a week goal.
/// Views should not re-parse `rawTitle` themselves.
public enum FacetAssociation {
    public enum Kind: Equatable, Sendable {
        case item(workPrefix: String, content: String)
        case weekGoal(workPrefix: String, title: String)
        case none
    }

    /// Classify a raw EventKit title (and optional notes) into a FacetX association.
    public static func classify(title: String, notes: String? = nil) -> Kind {
        guard let prefix = WorkPrefix.workName(of: title) else {
            return .none
        }
        let content = WorkPrefix.contentBody(of: title)
        if WeekGoalEvent.hasGoalMetadata(notes, work: prefix) {
            return .weekGoal(workPrefix: prefix, title: content)
        }
        return .item(workPrefix: prefix, content: content)
    }
}
