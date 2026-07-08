import Foundation

struct ProjectDraft: Identifiable {
    let id = UUID()
    var name: String
    var prefix: String
    var tagline = ""
    var reminderListName: String
    var calendarName: String
    var noteCalendarName: String
    var weekGoalCalendarName: String
    var literatureListName: String
    var dataDirectory: String = ""
    var githubRepo: String = ""
    var colorName: String = ProjectAppearance.defaultColorName
    var iconName: String = ProjectAppearance.defaultIconName
    var reminderLists: [String]
    var calendars: [String]
}
