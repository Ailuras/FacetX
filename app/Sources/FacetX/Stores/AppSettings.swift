import Foundation
import SwiftUI

/// User settings, persisted as JSON under Application Support.
///
/// `enabledReminderListNames` and `enabledCalendarNames` hold the *titles* of
/// containers FacetX is allowed to read and write. Titles (not
/// calendarIdentifiers) are used deliberately: identifiers are device-local —
/// the same iCloud calendar has a different id on each Mac — whereas the title
/// is stable across devices.
///
/// An EMPTY set means "all containers of that kind" (the fresh-install
/// default). Reminder and calendar selections are split so same-title
/// containers do not toggle each other accidentally.
@MainActor
final class AppSettings: ObservableObject {
    @Published var enabledReminderListNames: Set<String> {
        didSet { settingsDidChange() }
    }
    @Published var enabledCalendarNames: Set<String> {
        didSet { settingsDidChange() }
    }
    @Published var reminderListsDisabled: Bool {
        didSet { settingsDidChange() }
    }
    @Published var calendarsDisabled: Bool {
        didSet { settingsDidChange() }
    }
    @Published var defaultReminderListName: String {
        didSet { settingsDidChange() }
    }
    @Published var defaultCalendarName: String {
        didSet { settingsDidChange() }
    }
    @Published var weekGoalCalendarName: String {
        didSet { settingsDidChange() }
    }
    @Published var defaultLiteratureListName: String {
        didSet { settingsDidChange() }
    }
    @Published var menuBarEnabled: Bool {
        didSet { settingsDidChange() }
    }
    /// Whether the desktop widget panel (glass dashboard pinned to the desktop
    /// layer) is shown.
    @Published var desktopWidgetEnabled: Bool {
        didSet { settingsDidChange() }
    }
    /// Default focus (pomodoro) session length in minutes.
    @Published var focusDurationMinutes: Int {
        didSet { settingsDidChange() }
    }
    /// UI language, "en" or "zh" (default English). Read into `L10n.language`
    /// at launch; switching it persists the choice and prompts a restart rather
    /// than refreshing the UI live, so every view renders the same language.
    @Published var language: String {
        didSet { settingsDidChange() }
    }
    /// Startup behavior: "none" (open nothing), "last" (reopen the last project),
    /// or "specific" (always open `startupProjectID`).
    @Published var startupProjectMode: String {
        didSet { settingsDidChange() }
    }
    /// Project id opened on launch when `startupProjectMode == "specific"` and
    /// `startupSelectionKind == "project"`.
    @Published var startupProjectID: String {
        didSet { settingsDidChange() }
    }
    /// Whether the "specific" startup target is a project or a literature library.
    /// "project" or "topic".
    @Published var startupSelectionKind: String {
        didSet { settingsDidChange() }
    }
    /// Topic (literature library) id opened on launch when the specific target is
    /// a library.
    @Published var startupTopicID: String {
        didSet { settingsDidChange() }
    }
    /// Last project the user had selected, reopened on launch when
    /// `startupProjectMode == "last"`. Saved without bumping `changeToken` since
    /// it updates on every project switch.
    @Published var lastOpenedProjectID: String {
        didSet { save() }
    }
    /// Whether the last opened sidebar item was a project or a literature library.
    /// "project" or "topic".
    @Published var lastOpenedKind: String {
        didSet { save() }
    }
    /// Last literature library the user had selected, reopened on launch when
    /// `startupProjectMode == "last"` and `lastOpenedKind == "topic"`.
    @Published var lastOpenedTopicID: String {
        didSet { save() }
    }
    @Published var defaultEventDurationMinutes: Int {
        didSet { settingsDidChange() }
    }
    @Published var todayViewMode: String {
        didSet { settingsDidChange() }
    }
    @Published var todayTimelineStartHour: Int {
        didSet { settingsDidChange() }
    }
    @Published var todayTimelineEndHour: Int {
        didSet { settingsDidChange() }
    }
    @Published var githubToken: String {
        didSet { settingsDidChange() }
    }
    @Published var globalShortcutEnabled: Bool {
        didSet { settingsDidChange() }
    }
    /// Raw `SwipeAction` value for a swipe-right (leading edge) on an item row.
    @Published var leadingSwipeAction: String {
        didSet { settingsDidChange() }
    }
    /// Raw `SwipeAction` value for a swipe-left (trailing edge) on an item row.
    @Published var trailingSwipeAction: String {
        didSet { settingsDidChange() }
    }
    /// Tag name → color name mapping. Uses the same color names as ProjectAppearance.
    @Published var tagColors: [String: String] {
        didSet { settingsDidChange() }
    }
    @Published private(set) var changeToken = 0
    @Published private(set) var persistenceError: String?

    private let url: URL

    init(filename: String = "settings.json") {
        self.url = AppSupport.directory().appendingPathComponent(filename)
        var persistenceError: String?
        let stored: Stored
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                stored = try JSONDecoder().decode(Stored.self, from: data)
            } catch {
                stored = .defaults
                persistenceError = "Could not read settings.json: \(error.localizedDescription)"
            }
        } else {
            stored = .defaults
        }
        self.enabledReminderListNames = Set(stored.enabledReminderListNames)
        self.enabledCalendarNames = Set(stored.enabledCalendarNames)
        self.reminderListsDisabled = stored.reminderListsDisabled
        self.calendarsDisabled = stored.calendarsDisabled
        self.defaultReminderListName = stored.defaultReminderListName
        self.defaultCalendarName = stored.defaultCalendarName
        self.weekGoalCalendarName = stored.weekGoalCalendarName
        self.defaultLiteratureListName = stored.defaultLiteratureListName ?? ""
        self.menuBarEnabled = stored.menuBarEnabled
        self.desktopWidgetEnabled = stored.desktopWidgetEnabled ?? true
        self.focusDurationMinutes = stored.focusDurationMinutes ?? 25
        self.language = stored.language ?? "en"
        self.startupProjectMode = stored.startupProjectMode ?? "none"
        self.startupProjectID = stored.startupProjectID ?? ""
        self.startupSelectionKind = stored.startupSelectionKind ?? "project"
        self.startupTopicID = stored.startupTopicID ?? ""
        self.lastOpenedProjectID = stored.lastOpenedProjectID ?? ""
        self.lastOpenedKind = stored.lastOpenedKind ?? "project"
        self.lastOpenedTopicID = stored.lastOpenedTopicID ?? ""
        let durationPresets = [15, 30, 45, 60, 90, 120, 180, 240]
        let rawDuration = stored.defaultEventDurationMinutes
        self.defaultEventDurationMinutes = durationPresets.min(by: { abs($0 - rawDuration) < abs($1 - rawDuration) }) ?? 60
        self.todayViewMode = stored.todayViewMode
        self.todayTimelineStartHour = stored.todayTimelineStartHour
        self.todayTimelineEndHour = stored.todayTimelineEndHour
        self.githubToken = stored.githubToken ?? ""
        self.globalShortcutEnabled = stored.globalShortcutEnabled
        self.leadingSwipeAction = stored.leadingSwipeAction ?? "tomorrow"
        self.trailingSwipeAction = stored.trailingSwipeAction ?? "today"
        self.tagColors = stored.tagColors ?? [:]
        self.persistenceError = persistenceError
        L10n.language = self.language
    }

    /// Is this reminder list enabled? Empty config = all reminder lists enabled.
    func isReminderListEnabled(_ name: String) -> Bool {
        guard !reminderListsDisabled else { return false }
        return enabledReminderListNames.isEmpty || enabledReminderListNames.contains(name)
    }

    /// Is this calendar enabled? Empty config = all calendars enabled.
    func isCalendarEnabled(_ name: String) -> Bool {
        guard !calendarsDisabled else { return false }
        return enabledCalendarNames.isEmpty || enabledCalendarNames.contains(name)
    }

    var effectiveReminderListNames: Set<String>? {
        reminderListsDisabled ? [] : (enabledReminderListNames.isEmpty ? nil : enabledReminderListNames)
    }

    var effectiveCalendarNames: Set<String>? {
        calendarsDisabled ? [] : (enabledCalendarNames.isEmpty ? nil : enabledCalendarNames)
    }

    func reminderSaveTarget(projectListName: String?) -> String {
        saveTarget(preferred: projectListName,
                   fallback: defaultReminderListName,
                   disabled: reminderListsDisabled,
                   enabledNames: enabledReminderListNames)
    }

    func calendarSaveTarget(projectCalendarName: String?) -> String {
        saveTarget(preferred: projectCalendarName,
                   fallback: defaultCalendarName,
                   disabled: calendarsDisabled,
                   enabledNames: enabledCalendarNames)
    }

    private func saveTarget(preferred: String?, fallback: String,
                            disabled: Bool, enabledNames: Set<String>) -> String {
        guard !disabled else { return "" }
        if let preferred = enabledContainerName(preferred, enabledNames: enabledNames) {
            return preferred
        }
        return enabledContainerName(fallback, enabledNames: enabledNames) ?? ""
    }

    private func enabledContainerName(_ name: String?, enabledNames: Set<String>) -> String? {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return nil }
        return enabledNames.isEmpty || enabledNames.contains(name) ? name : nil
    }

    /// Resolve a tag's color. If explicitly set, returns that; otherwise picks a
    /// deterministic color from the palette based on the tag name's hash so the
    /// same tag always renders the same color across launches.
    func tagColor(for tag: String) -> Color {
        ProjectAppearance.color(for: tagColorName(for: tag))
    }

    func tagColorName(for tag: String) -> String {
        if let name = tagColors[tag] { return name }
        let palette = ProjectAppearance.colors
        var hash = 5381
        for byte in tag.utf8 { hash = ((hash << 5) &+ hash) &+ Int(byte) }
        let index = abs(hash) % palette.count
        return palette[index].id
    }

    func setTagColor(_ tag: String, colorName: String) {
        tagColors[tag] = colorName
        settingsDidChange()
    }

    func useAllContainers() {
        reminderListsDisabled = false
        calendarsDisabled = false
        enabledReminderListNames = []
        enabledCalendarNames = []
    }

    func disableAllContainers() {
        reminderListsDisabled = true
        calendarsDisabled = true
        enabledReminderListNames = []
        enabledCalendarNames = []
        defaultReminderListName = ""
        defaultCalendarName = ""
        weekGoalCalendarName = ""
        defaultLiteratureListName = ""
    }

    /// Ensure `name` is enabled. If config is "all" (empty), it stays all —
    /// the name is already implicitly enabled.
    func enableReminderList(_ name: String) {
        reminderListsDisabled = false
        if !enabledReminderListNames.isEmpty { enabledReminderListNames.insert(name) }
    }

    func enableCalendar(_ name: String) {
        calendarsDisabled = false
        if !enabledCalendarNames.isEmpty { enabledCalendarNames.insert(name) }
    }

    func toggleReminderList(_ name: String, allNames: [String]) {
        if reminderListsDisabled {
            reminderListsDisabled = false
            enabledReminderListNames = [name]
            return
        }
        // Materialize "all" into an explicit set before the first removal, so
        // unchecking one doesn't accidentally enable everything else.
        if enabledReminderListNames.isEmpty { enabledReminderListNames = Set(allNames) }
        if enabledReminderListNames.contains(name) { enabledReminderListNames.remove(name) }
        else { enabledReminderListNames.insert(name) }
        if !isReminderListEnabled(defaultReminderListName) { defaultReminderListName = "" }
        if !isReminderListEnabled(defaultLiteratureListName) { defaultLiteratureListName = "" }
    }

    func toggleCalendar(_ name: String, allNames: [String]) {
        if calendarsDisabled {
            calendarsDisabled = false
            enabledCalendarNames = [name]
            return
        }
        if enabledCalendarNames.isEmpty { enabledCalendarNames = Set(allNames) }
        if enabledCalendarNames.contains(name) { enabledCalendarNames.remove(name) }
        else { enabledCalendarNames.insert(name) }
        if !isCalendarEnabled(defaultCalendarName) { defaultCalendarName = "" }
        if !isCalendarEnabled(weekGoalCalendarName) { weekGoalCalendarName = "" }
    }

    private struct Stored: Codable {
        var enabledReminderListNames: [String]
        var enabledCalendarNames: [String]
        var reminderListsDisabled: Bool
        var calendarsDisabled: Bool
        var defaultReminderListName: String
        var defaultCalendarName: String
        var weekGoalCalendarName: String
        var defaultLiteratureListName: String?
        var menuBarEnabled: Bool
        var desktopWidgetEnabled: Bool?
        var focusDurationMinutes: Int?
        var language: String?
        var startupProjectMode: String?
        var startupProjectID: String?
        var startupSelectionKind: String?
        var startupTopicID: String?
        var lastOpenedProjectID: String?
        var lastOpenedKind: String?
        var lastOpenedTopicID: String?
        var defaultEventDurationMinutes: Int
        var todayViewMode: String
        var todayTimelineStartHour: Int
        var todayTimelineEndHour: Int
        var githubToken: String?
        var globalShortcutEnabled: Bool
        var leadingSwipeAction: String?
        var trailingSwipeAction: String?
        var tagColors: [String: String]?

        static let defaults = Stored(enabledReminderListNames: [],
                                     enabledCalendarNames: [],
                                     reminderListsDisabled: false,
                                     calendarsDisabled: false,
                                     defaultReminderListName: "",
                                     defaultCalendarName: "",
                                     weekGoalCalendarName: "",
                                     defaultLiteratureListName: "",
                                     menuBarEnabled: true,
                                     desktopWidgetEnabled: nil,
                                     focusDurationMinutes: nil,
                                     language: nil,
                                     startupProjectMode: nil,
                                     startupProjectID: nil,
                                     startupSelectionKind: nil,
                                     startupTopicID: nil,
                                     lastOpenedProjectID: nil,
                                     lastOpenedKind: nil,
                                     lastOpenedTopicID: nil,
                                     defaultEventDurationMinutes: 120,
                                     todayViewMode: "list",
                                     todayTimelineStartHour: 6,
                                     todayTimelineEndHour: 23,
                                     githubToken: nil,
                                     globalShortcutEnabled: false,
                                     leadingSwipeAction: "tomorrow",
                                     trailingSwipeAction: "today",
                                     tagColors: [:])
    }

    private func save() {
        let stored = Stored(enabledReminderListNames: enabledReminderListNames.sorted(),
                            enabledCalendarNames: enabledCalendarNames.sorted(),
                            reminderListsDisabled: reminderListsDisabled,
                            calendarsDisabled: calendarsDisabled,
                            defaultReminderListName: defaultReminderListName,
                            defaultCalendarName: defaultCalendarName,
                            weekGoalCalendarName: weekGoalCalendarName,
                            defaultLiteratureListName: defaultLiteratureListName,
                            menuBarEnabled: menuBarEnabled,
                            desktopWidgetEnabled: desktopWidgetEnabled,
                            focusDurationMinutes: focusDurationMinutes,
                            language: language,
                            startupProjectMode: startupProjectMode,
                            startupProjectID: startupProjectID.isEmpty ? nil : startupProjectID,
                            startupSelectionKind: startupSelectionKind,
                            startupTopicID: startupTopicID.isEmpty ? nil : startupTopicID,
                            lastOpenedProjectID: lastOpenedProjectID.isEmpty ? nil : lastOpenedProjectID,
                            lastOpenedKind: lastOpenedKind,
                            lastOpenedTopicID: lastOpenedTopicID.isEmpty ? nil : lastOpenedTopicID,
                            defaultEventDurationMinutes: defaultEventDurationMinutes,
                            todayViewMode: todayViewMode,
                            todayTimelineStartHour: todayTimelineStartHour,
                            todayTimelineEndHour: todayTimelineEndHour,
                            githubToken: githubToken.isEmpty ? nil : githubToken,
                            globalShortcutEnabled: globalShortcutEnabled,
                            leadingSwipeAction: leadingSwipeAction,
                            trailingSwipeAction: trailingSwipeAction,
                            tagColors: tagColors)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try enc.encode(stored).write(to: url, options: .atomic)
            persistenceError = nil
        } catch {
            persistenceError = "Could not write settings.json: \(error.localizedDescription)"
        }
    }

    private func settingsDidChange() {
        save()
        changeToken &+= 1
    }
}
