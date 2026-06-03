import Foundation

struct ProjectDraft: Identifiable {
    let id = UUID()
    var name: String
    var prefix: String
    var tagline = ""
    var reminderListName: String
    var calendarName: String
    var weekGoalCalendarName: String
    var githubRepo: String = ""
    var reminderLists: [String]
    var calendars: [String]
}
