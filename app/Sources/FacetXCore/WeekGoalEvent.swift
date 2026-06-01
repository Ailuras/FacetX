import Foundation

/// Shared title convention for week-goal calendar events.
public enum WeekGoalEvent {
    public static let marker = "🎯 "

    public static func content(title: String) -> String {
        marker + title
    }

    public static func isGoalContent(_ content: String) -> Bool {
        content.hasPrefix(marker)
    }

    public static func makeTitle(project: String, title: String) -> String {
        ProjectPrefix.makeTitle(project: project, content: content(title: title))
    }
}
