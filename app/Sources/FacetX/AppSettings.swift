import Foundation

/// User settings, persisted as JSON under Application Support.
///
/// `enabledReminderListNames` and `enabledCalendarNames` hold the *titles* of
/// containers FacetX is allowed to read and write. Titles (not
/// calendarIdentifiers) are used deliberately: identifiers are device-local —
/// the same iCloud calendar has a different id on each Mac — whereas the title
/// is stable across devices.
///
/// An EMPTY set means "all containers of that kind" (the default — preserves
/// the original no-filter behavior so a fresh install just works). Reminder and
/// calendar selections are split so same-title containers do not toggle each
/// other accidentally.
@MainActor
final class AppSettings: ObservableObject {
    @Published var enabledReminderListNames: Set<String> {
        didSet { settingsDidChange() }
    }
    @Published var enabledCalendarNames: Set<String> {
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
    @Published var menuBarEnabled: Bool {
        didSet { settingsDidChange() }
    }
    @Published private(set) var changeToken = 0
    @Published private(set) var persistenceError: String?

    private let url: URL

    init(filename: String = "settings.json") {
        self.url = AppSupport.directory().appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: url.path) {
            let stored: Stored?
            do {
                let data = try Data(contentsOf: url)
                stored = try JSONDecoder().decode(Stored.self, from: data)
                self.persistenceError = nil
            } catch {
                stored = nil
                self.persistenceError = "Could not read settings.json: \(error.localizedDescription)"
            }

            if let stored {
                if let reminderNames = stored.enabledReminderListNames,
                   let calendarNames = stored.enabledCalendarNames {
                    self.enabledReminderListNames = Set(reminderNames)
                    self.enabledCalendarNames = Set(calendarNames)
                } else {
                    let legacy = Set(stored.enabledContainerNames ?? [])
                    self.enabledReminderListNames = legacy
                    self.enabledCalendarNames = legacy
                }
                self.defaultReminderListName = stored.defaultReminderListName ?? ""
                self.defaultCalendarName = stored.defaultCalendarName ?? ""
                self.weekGoalCalendarName = stored.weekGoalCalendarName ?? ""
                self.menuBarEnabled = stored.menuBarEnabled ?? true
            } else {
                self.enabledReminderListNames = []
                self.enabledCalendarNames = []
                self.defaultReminderListName = ""
                self.defaultCalendarName = ""
                self.weekGoalCalendarName = ""
                self.menuBarEnabled = true
            }
        } else {
            self.enabledReminderListNames = []   // empty = all reminders
            self.enabledCalendarNames = []       // empty = all calendars
            self.defaultReminderListName = ""
            self.defaultCalendarName = ""
            self.weekGoalCalendarName = ""
            self.menuBarEnabled = true
        }
    }

    /// Is this reminder list enabled? Empty config = all reminder lists enabled.
    func isReminderListEnabled(_ name: String) -> Bool {
        enabledReminderListNames.isEmpty || enabledReminderListNames.contains(name)
    }

    /// Is this calendar enabled? Empty config = all calendars enabled.
    func isCalendarEnabled(_ name: String) -> Bool {
        enabledCalendarNames.isEmpty || enabledCalendarNames.contains(name)
    }

    func useAllContainers() {
        enabledReminderListNames = []
        enabledCalendarNames = []
    }

    /// Ensure `name` is enabled. If config is "all" (empty), it stays all —
    /// the name is already implicitly enabled.
    func enableReminderList(_ name: String) {
        if !enabledReminderListNames.isEmpty { enabledReminderListNames.insert(name) }
    }

    func enableCalendar(_ name: String) {
        if !enabledCalendarNames.isEmpty { enabledCalendarNames.insert(name) }
    }

    func toggleReminderList(_ name: String, allNames: [String]) {
        // Materialize "all" into an explicit set before the first removal, so
        // unchecking one doesn't accidentally enable everything else.
        if enabledReminderListNames.isEmpty { enabledReminderListNames = Set(allNames) }
        if enabledReminderListNames.contains(name) { enabledReminderListNames.remove(name) }
        else { enabledReminderListNames.insert(name) }
        if !isReminderListEnabled(defaultReminderListName) { defaultReminderListName = "" }
    }

    func toggleCalendar(_ name: String, allNames: [String]) {
        if enabledCalendarNames.isEmpty { enabledCalendarNames = Set(allNames) }
        if enabledCalendarNames.contains(name) { enabledCalendarNames.remove(name) }
        else { enabledCalendarNames.insert(name) }
        if !isCalendarEnabled(defaultCalendarName) { defaultCalendarName = "" }
        if !isCalendarEnabled(weekGoalCalendarName) { weekGoalCalendarName = "" }
    }

    private struct Stored: Codable {
        var enabledReminderListNames: [String]?
        var enabledCalendarNames: [String]?
        var enabledContainerNames: [String]?
        var defaultReminderListName: String?
        var defaultCalendarName: String?
        var weekGoalCalendarName: String?
        var menuBarEnabled: Bool?
    }

    private func save() {
        let stored = Stored(enabledReminderListNames: enabledReminderListNames.sorted(),
                            enabledCalendarNames: enabledCalendarNames.sorted(),
                             enabledContainerNames: nil,
                             defaultReminderListName: defaultReminderListName,
                             defaultCalendarName: defaultCalendarName,
                             weekGoalCalendarName: weekGoalCalendarName,
                             menuBarEnabled: menuBarEnabled)
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
