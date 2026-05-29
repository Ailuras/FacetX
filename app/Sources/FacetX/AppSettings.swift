import Foundation

/// User settings, persisted as JSON under Application Support.
///
/// `enabledContainerNames` holds the *titles* of calendars / reminder lists
/// FacetX is allowed to read and write. Titles (not calendarIdentifiers) are
/// used deliberately: identifiers are device-local — the same iCloud calendar
/// has a different id on each Mac — whereas the title is stable across devices,
/// so this config survives syncing the app across multiple machines that may
/// even use different Apple accounts.
///
/// An EMPTY set means "all containers" (the default — preserves the original
/// no-filter behavior so a fresh install just works).
@MainActor
final class AppSettings: ObservableObject {
    @Published var enabledContainerNames: Set<String> {
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
            self.enabledContainerNames = Set(stored.enabledContainerNames)
            self.defaultReminderListName = stored.defaultReminderListName ?? ""
            self.defaultCalendarName = stored.defaultCalendarName ?? ""
            self.menuBarEnabled = stored.menuBarEnabled ?? true
        } else {
            self.enabledContainerNames = []   // empty = all
            self.defaultReminderListName = ""
            self.defaultCalendarName = ""
            self.menuBarEnabled = true
        }
    }

    /// Is this container enabled? Empty config = everything enabled.
    func isEnabled(_ name: String) -> Bool {
        enabledContainerNames.isEmpty || enabledContainerNames.contains(name)
    }

    /// Ensure `name` is enabled. If config is "all" (empty), it stays all —
    /// the name is already implicitly enabled.
    func enable(_ name: String) {
        if !enabledContainerNames.isEmpty { enabledContainerNames.insert(name) }
    }

    func toggle(_ name: String, allNames: [String]) {
        // Materialize "all" into an explicit set before the first removal, so
        // unchecking one doesn't accidentally enable everything else.
        if enabledContainerNames.isEmpty { enabledContainerNames = Set(allNames) }
        if enabledContainerNames.contains(name) { enabledContainerNames.remove(name) }
        else { enabledContainerNames.insert(name) }
        if !isEnabled(defaultReminderListName) { defaultReminderListName = "" }
        if !isEnabled(defaultCalendarName) { defaultCalendarName = "" }
    }

    private struct Stored: Codable {
        var enabledContainerNames: [String]
        var defaultReminderListName: String?
        var defaultCalendarName: String?
        var menuBarEnabled: Bool?
    }

    private func save() {
        let stored = Stored(enabledContainerNames: enabledContainerNames.sorted(),
                            defaultReminderListName: defaultReminderListName,
                            defaultCalendarName: defaultCalendarName,
                            menuBarEnabled: menuBarEnabled)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(stored).write(to: url, options: .atomic)
    }
}
