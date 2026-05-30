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
        didSet { save() }
    }
    @Published var enabledCalendarNames: Set<String> {
        didSet { save() }
    }
    @Published var defaultReminderListName: String {
        didSet { save() }
    }
    @Published var defaultCalendarName: String {
        didSet { save() }
    }
    @Published var menuBarEnabled: Bool {
        didSet { save() }
    }

    private let url: URL

    init(filename: String = "settings.json") {
        self.url = AppSupport.directory().appendingPathComponent(filename)
        if let data = try? Data(contentsOf: url),
           let stored = try? JSONDecoder().decode(Stored.self, from: data) {
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
            self.menuBarEnabled = stored.menuBarEnabled ?? true
        } else {
            self.enabledReminderListNames = []   // empty = all reminders
            self.enabledCalendarNames = []       // empty = all calendars
            self.defaultReminderListName = ""
            self.defaultCalendarName = ""
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
    }

    private struct Stored: Codable {
        var enabledReminderListNames: [String]?
        var enabledCalendarNames: [String]?
        var enabledContainerNames: [String]?
        var defaultReminderListName: String?
        var defaultCalendarName: String?
        var menuBarEnabled: Bool?
    }

    private func save() {
        let stored = Stored(enabledReminderListNames: enabledReminderListNames.sorted(),
                            enabledCalendarNames: enabledCalendarNames.sorted(),
                            enabledContainerNames: nil,
                            defaultReminderListName: defaultReminderListName,
                            defaultCalendarName: defaultCalendarName,
                            menuBarEnabled: menuBarEnabled)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(stored).write(to: url, options: .atomic)
    }
}
