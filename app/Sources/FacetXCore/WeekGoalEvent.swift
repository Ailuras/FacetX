import Foundation

/// Shared title convention for week-goal calendar events.
public enum WeekGoalEvent {
    private static let kindKey = "facetx-kind"
    private static let projectKey = "facetx-project"
    private static let weekKey = "facetx-week"
    private static let goalKind = "week-goal"

    public static func makeTitle(project: String, title: String) -> String {
        ProjectPrefix.makeTitle(project: project, content: title)
    }

    public static func makeNotes(body: String, project: String, weekID: String) -> String {
        let metadata = FacetMetadata(
            fields: [
                kindKey: goalKind,
                projectKey: project,
                weekKey: weekID
            ]
        )
        return FacetMetadata.compose(userNotes: body, metadata: metadata) ?? ""
    }

    public static func body(fromNotes notes: String?) -> String {
        FacetMetadata.parse(notes: notes).userNotes
    }

    public static func hasGoalMetadata(_ notes: String?, project: String? = nil, weekID: String? = nil) -> Bool {
        let fields = FacetMetadata.parse(notes: notes).fields
        guard fields[kindKey] == goalKind else { return false }
        if let project, fields[projectKey] != project { return false }
        if let weekID, fields[weekKey] != weekID { return false }
        return true
    }
}
