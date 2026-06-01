import Foundation

/// Shared title convention for week-goal calendar events.
public enum WeekGoalEvent {
    public static let marker = "🎯 "
    public static let notesMarkerPrefix = "FacetX-WeekGoal:"

    public static func content(title: String) -> String {
        marker + title
    }

    public static func isGoalContent(_ content: String) -> Bool {
        content.hasPrefix(marker)
    }

    public static func title(fromContent content: String) -> String {
        guard isGoalContent(content) else { return content }
        return String(content.dropFirst(marker.count))
    }

    public static func makeTitle(project: String, title: String) -> String {
        ProjectPrefix.makeTitle(project: project, content: content(title: title))
    }

    public static func makeNotes(body: String, project: String, weekID: String) -> String {
        let markerLine = notesMarker(project: project, weekID: weekID)
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? markerLine : "\(trimmed)\n\n\(markerLine)"
    }

    public static func body(fromNotes notes: String?) -> String {
        guard let notes else { return "" }
        let lines = notes.components(separatedBy: .newlines)
            .filter { !$0.hasPrefix(notesMarkerPrefix) }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func hasNotesMarker(_ notes: String?, project: String, weekID: String) -> Bool {
        notes?.contains(notesMarker(project: project, weekID: weekID)) == true
    }

    private static func notesMarker(project: String, weekID: String) -> String {
        "\(notesMarkerPrefix) \(project) | \(weekID)"
    }
}
