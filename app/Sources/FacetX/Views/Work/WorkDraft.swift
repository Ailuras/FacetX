import Foundation

struct WorkDraft: Identifiable {
    let id = UUID()
    var name: String
    var prefix: String
    var tagline = ""
    var reminderListName: String
    var calendarName: String
    var weekGoalCalendarName: String
    var githubRepo: String = ""
    var githubLocalPath: String = ""
    var colorName: String = WorkAppearance.defaultColorName
    var iconName: String = WorkAppearance.defaultIconName
    var reminderLists: [String]
    var calendars: [String]
}
