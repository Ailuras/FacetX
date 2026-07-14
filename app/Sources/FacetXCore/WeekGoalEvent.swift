import Foundation

/// Shared title convention for week-goal calendar events.
public enum WeekGoalEvent {
    private static let kindKey = "facetx-kind"
    private static let workKey = "facetx-work"
    private static let weekKey = "facetx-week"
    private static let goalKind = "week-goal"

    public static func makeTitle(work: String, title: String) -> String {
        WorkPrefix.makeTitle(work: work, content: title)
    }

    public static func makeNotes(body: String, work: String, weekID: String) -> String {
        let metadata = FacetMetadata(
            fields: [
                kindKey: goalKind,
                workKey: work,
                weekKey: weekID
            ]
        )
        return FacetMetadata.compose(userNotes: body, metadata: metadata) ?? ""
    }

    public static func body(fromNotes notes: String?) -> String {
        FacetMetadata.parse(notes: notes).userNotes
    }

    public static func hasGoalMetadata(_ notes: String?, work: String? = nil, weekID: String? = nil) -> Bool {
        let fields = FacetMetadata.parse(notes: notes).fields
        guard fields[kindKey] == goalKind else { return false }
        if let work, fields[workKey] != work { return false }
        if let weekID, fields[weekKey] != weekID { return false }
        return true
    }
}
