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
    var githubLocalPath: String = ""
    var colorName: String = ProjectAppearance.defaultColorName
    var iconName: String = ProjectAppearance.defaultIconName
    var reminderLists: [String]
    var calendars: [String]
}
