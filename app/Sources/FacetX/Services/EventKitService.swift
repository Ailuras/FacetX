import EventKit
import FacetXCore
import Foundation

struct WeekGoalEventSnapshot: Sendable {
    let eventId: String
    let title: String
    let body: String
}

/// Wraps EKEventStore: authorization, fetching, prefix-filtering, write-back.
///
/// NOT `@MainActor`: EventKit's fetch callbacks fire on its own background
/// queue, and EKEventStore is not Sendable, so a main-actor-isolated wrapper
/// triggers Swift 6 isolation assertions (SIGTRAP) and data-race diagnostics.
/// Instead the class is nonisolated; only the @Published auth flags are written
/// back on the main actor.
final class EventKitService: ObservableObject, @unchecked Sendable {
    private let store = EKEventStore()

    @Published var remindersAuthorized = false
    @Published var calendarAuthorized = false
    /// Bumped whenever EventKit's data changes (here, in Apple's apps, or via
    /// iCloud). Views observe this to refresh live, Fantastical-style.
    @Published var changeToken = 0

    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            self?.changeToken &+= 1
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func requestAccess() async {
        let reminders = (try? await store.requestFullAccessToReminders()) ?? false
        let calendar = (try? await store.requestFullAccessToEvents()) ?? false
        await MainActor.run {
            self.remindersAuthorized = reminders
            self.calendarAuthorized = calendar
        }
    }

    /// Filter a container list by enabled titles. `nil` = all; empty set = none.
    private func filtered(_ calendars: [EKCalendar], by enabled: Set<String>?) -> [EKCalendar] {
        guard let enabled else { return calendars }
        return calendars.filter { enabled.contains($0.title) }
    }

    /// All items (reminders + events) whose title prefix matches `project`,
    /// limited to the enabled containers (empty/nil = all).
    func items(forProject project: String,
               enabledReminderLists: Set<String>? = nil,
               enabledCalendars: Set<String>? = nil,
               eventStartDate: Date? = nil,
               eventEndDate: Date? = nil,
               eventWindowDays: Int = 120) async -> [ProjectItem] {
        await items(forProjects: [project],
                    enabledReminderLists: enabledReminderLists,
                    enabledCalendars: enabledCalendars,
                    eventStartDate: eventStartDate,
                    eventEndDate: eventEndDate,
                    eventWindowDays: eventWindowDays)
    }

    /// All items across several projects in one pass, for cross-project views
    /// like Today. `prefixes` are the claimed project prefixes to keep.
    func items(forProjects prefixes: Set<String>,
               enabledReminderLists: Set<String>? = nil,
               enabledCalendars: Set<String>? = nil,
               eventStartDate: Date? = nil,
               eventEndDate: Date? = nil,
               eventWindowDays: Int = 120) async -> [ProjectItem] {
        guard !prefixes.isEmpty else { return [] }
        let (rem, cal) = await MainActor.run { (remindersAuthorized, calendarAuthorized) }
        var result: [ProjectItem] = []
        if rem { result += await reminders(forProjects: prefixes, enabled: enabledReminderLists) }
        if cal {
            result += events(forProjects: prefixes, enabled: enabledCalendars,
                             startDate: eventStartDate, endDate: eventEndDate,
                             windowDays: eventWindowDays)
        }
        return result.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }

    /// Paper backlinks are resource relationships, not schedule queries. Use a
    /// wide event range so old literature events still count as linked.
    func itemsLinkedToPapers(forProjects prefixes: Set<String>,
                             enabledReminderLists: Set<String>? = nil,
                             enabledCalendars: Set<String>? = nil) async -> [ProjectItem] {
        guard !prefixes.isEmpty else { return [] }
        let (rem, cal) = await MainActor.run { (remindersAuthorized, calendarAuthorized) }
        var result: [ProjectItem] = []
        if rem {
            result += await reminders(forProjects: prefixes, enabled: enabledReminderLists)
                .filter { !$0.linkedPaperIDs.isEmpty }
        }
        if cal {
            result += events(forProjects: prefixes,
                             enabled: enabledCalendars,
                             startDate: Self.paperLinkScanStartDate,
                             endDate: Self.paperLinkScanEndDate,
                             windowDays: 0)
                .filter { !$0.linkedPaperIDs.isEmpty }
        }
        return result.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }

    /// Distinct project names discovered across enabled reminders + recent events.
    func discoverProjectNames(enabledReminderLists: Set<String>? = nil,
                              enabledCalendars: Set<String>? = nil,
                              eventWindowDays: Int = 120) async -> [String] {
        let (rem, cal) = await MainActor.run { (remindersAuthorized, calendarAuthorized) }
        var names = Set<String>()
        if rem {
            // Map to project names inside the callback; EKReminder is not Sendable.
            let discovered = await fetchReminderProjectNames(enabled: enabledReminderLists)
            names.formUnion(discovered)
        }
        if cal {
            for e in recentEvents(enabled: enabledCalendars, windowDays: eventWindowDays) {
                if let n = ProjectPrefix.projectName(of: e.title ?? "") { names.insert(n) }
            }
        }
        return names.sorted()
    }

    // ── Reminders ──────────────────────────────────────────────────────────

    /// Fetch reminders and flatten matching ones to Sendable ProjectItems inside
    /// the EventKit callback, so no non-Sendable EKReminder crosses an actor hop.
    ///
    /// The class is nonisolated, so fetchReminders' background-queue callback can
    /// run freely without tripping the Swift 6 main-actor isolation assertion
    /// (dispatch_assert_queue_fail → SIGTRAP) that crashed an earlier build.
    private func reminders(forProjects prefixes: Set<String>, enabled: Set<String>?) async -> [ProjectItem] {
        let lists = filtered(store.calendars(for: .reminder), by: enabled)
        guard !lists.isEmpty else { return [] }
        let pred = store.predicateForReminders(in: lists)
        return await withCheckedContinuation { cont in
            store.fetchReminders(matching: pred) { reminders in
                let items = (reminders ?? []).compactMap { r -> ProjectItem? in
                    let title = r.title ?? ""
                    guard case let .item(prefix, content) = FacetAssociation.classify(title: title, notes: r.notes),
                          prefixes.contains(prefix) else { return nil }
                    let metadata = FacetMetadata.parse(notes: r.notes)
                    let itemMetadata = FacetItemMetadata.parse(metadata)
                    return ProjectItem(
                        id: r.calendarItemIdentifier,
                        kind: .reminder,
                        rawTitle: title,
                        projectPrefix: prefix,
                        content: content,
                        containerName: r.calendar?.title ?? "?",
                        isCompleted: r.isCompleted,
                        date: r.dueDateComponents?.date,
                        notes: nil,
                        tags: metadata.tags,
                        priority: r.priority,
                        url: r.url,
                        hasTime: Self.hasReminderTime(r.dueDateComponents),
                        isAllDay: false,
                        endDate: nil,
                        facetID: itemMetadata?.itemID,
                        noteID: itemMetadata?.noteID,
                        linkedPaperIDs: itemMetadata?.paperIDs ?? [],
                        linkedCommits: itemMetadata?.commits ?? []
                    )
                }
                cont.resume(returning: items)
            }
        }
    }

    private func fetchReminderProjectNames(enabled: Set<String>?) async -> Set<String> {
        let lists = filtered(store.calendars(for: .reminder), by: enabled)
        guard !lists.isEmpty else { return [] }
        let pred = store.predicateForReminders(in: lists)
        return await withCheckedContinuation { cont in
            store.fetchReminders(matching: pred) { reminders in
                var names = Set<String>()
                for r in reminders ?? [] {
                    if let n = ProjectPrefix.projectName(of: r.title ?? "") { names.insert(n) }
                }
                cont.resume(returning: names)
            }
        }
    }

    // ── Events ─────────────────────────────────────────────────────────────

    private func events(forProjects prefixes: Set<String>, enabled: Set<String>?,
                        startDate: Date? = nil, endDate: Date? = nil,
                        windowDays: Int) -> [ProjectItem] {
        events(enabled: enabled, startDate: startDate, endDate: endDate, windowDays: windowDays).compactMap { e in
            let title = e.title ?? ""
            guard case let .item(prefix, content) = FacetAssociation.classify(title: title, notes: e.notes),
                  prefixes.contains(prefix) else { return nil }
            let metadata = FacetMetadata.parse(notes: e.notes)
            let itemMetadata = FacetItemMetadata.parse(metadata)
            return ProjectItem(
                id: e.calendarItemIdentifier,
                kind: .event,
                rawTitle: title,
                projectPrefix: prefix,
                content: content,
                containerName: e.calendar.title,
                isCompleted: false,
                date: e.startDate,
                notes: nil,
                tags: metadata.tags,
                priority: 0,
                url: e.url,
                hasTime: !e.isAllDay,
                isAllDay: e.isAllDay,
                endDate: e.endDate,
                facetID: itemMetadata?.itemID,
                noteID: itemMetadata?.noteID,
                linkedPaperIDs: itemMetadata?.paperIDs ?? [],
                linkedCommits: itemMetadata?.commits ?? []
            )
        }
    }

    private func recentEvents(enabled: Set<String>?, windowDays: Int) -> [EKEvent] {
        events(enabled: enabled, startDate: nil, endDate: nil, windowDays: windowDays)
    }

    private func events(enabled: Set<String>?, startDate: Date?, endDate: Date?, windowDays: Int) -> [EKEvent] {
        let cals = filtered(store.calendars(for: .event), by: enabled)
        guard !cals.isEmpty else { return [] }
        let now = Date()
        let start = startDate ?? Calendar.current.date(byAdding: .day, value: -windowDays, to: now)!
        let end = endDate ?? Calendar.current.date(byAdding: .day, value: windowDays, to: now)!
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: cals)
        return store.events(matching: pred)
    }

    // ── Containers (functional zones) ────────────────────────────────────────

    /// Names of reminder lists, optionally limited to enabled ones.
    func reminderListNames(enabled: Set<String>? = nil) -> [String] {
        filtered(store.calendars(for: .reminder), by: enabled).map(\.title).sorted()
    }

    /// Names of calendars, optionally limited to enabled ones.
    func calendarNames(enabled: Set<String>? = nil) -> [String] {
        filtered(store.calendars(for: .event), by: enabled).map(\.title).sorted()
    }

    /// A container as shown in Settings: its title, kind, and owning account.
    struct ContainerInfo: Identifiable, Hashable {
        enum Kind: String { case calendar = "Calendar", reminder = "Reminders" }
        var id: String { "\(kind.rawValue)/\(sourceTitle)/\(title)" }
        let title: String
        let kind: Kind
        let sourceTitle: String
    }

    /// All containers (calendars + reminder lists) for the Settings list,
    /// grouped-friendly with their owning account title.
    func allContainers() -> [ContainerInfo] {
        var result: [ContainerInfo] = []
        for c in store.calendars(for: .event) {
            result.append(.init(title: c.title, kind: .calendar, sourceTitle: c.source.title))
        }
        for c in store.calendars(for: .reminder) {
            result.append(.init(title: c.title, kind: .reminder, sourceTitle: c.source.title))
        }
        return result
    }

    // ── Write-back ───────────────────────────────────────────────────────────

    /// Toggle a reminder's completion by its identifier.
    func setReminderCompleted(id: String, completed: Bool) async {
        guard let item = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        item.isCompleted = completed
        try? store.save(item, commit: true)
    }

    /// Create a reminder titled `Project: content` in the named list.
    /// `dueDate` is optional. Returns the reminder's identifier on success, or nil.
    @discardableResult
    func createReminder(project: String, content: String,
                        listName: String, dueDate: Date?, dueIncludesTime: Bool,
                        tags: [String] = [],
                        itemMetadata: FacetItemMetadata? = nil,
                        priority: Int = 0, url: URL? = nil,
                        enabledLists: Set<String>? = nil) async -> String? {
        let lists = filtered(store.calendars(for: .reminder), by: enabledLists)
        guard let list = lists.first(where: { $0.title == listName })
        else { return nil }
        let r = EKReminder(eventStore: store)
        r.title = ProjectPrefix.makeTitle(project: project, content: content)
        r.calendar = list
        r.notes = composeItemNotes(tags: tags, itemMetadata: itemMetadata)
        r.priority = priority
        r.url = url
        if let due = dueDate {
            r.dueDateComponents = Self.reminderDueComponents(from: due, includesTime: dueIncludesTime)
        }
        do {
            try store.save(r, commit: true)
            return r.calendarItemIdentifier
        } catch {
            return nil
        }
    }

    /// Create a calendar event titled `Project: content` in the named calendar
    /// (= functional zone). Defaults to a 1-hour block at `startDate`.
    @discardableResult
    func createEvent(project: String, content: String,
                     calendarName: String, startDate: Date,
                     durationMinutes: Int = 60,
                     tags: [String] = [],
                     itemMetadata: FacetItemMetadata? = nil,
                     url: URL? = nil,
                     isAllDay: Bool = false, enabledCalendars: Set<String>? = nil) async -> String? {
        let calendars = filtered(store.calendars(for: .event), by: enabledCalendars)
        guard let cal = calendars.first(where: { $0.title == calendarName })
        else { return nil }
        let e = EKEvent(eventStore: store)
        e.title = ProjectPrefix.makeTitle(project: project, content: content)
        e.calendar = cal
        e.notes = composeItemNotes(tags: tags, itemMetadata: itemMetadata)
        e.url = url
        e.isAllDay = isAllDay
        if isAllDay {
            // All-day events span exactly one day in EventKit (end = start + 1 day, exclusive)
            e.startDate = Calendar.current.startOfDay(for: startDate)
            e.endDate = Calendar.current.date(byAdding: .day, value: 1, to: e.startDate)!
        } else {
            e.startDate = startDate
            e.endDate = Calendar.current.date(byAdding: .minute, value: durationMinutes, to: startDate)
        }
        do {
            try store.save(e, span: .thisEvent, commit: true)
            return e.calendarItemIdentifier
        } catch {
            return nil
        }
    }

    // ── Conversion helpers ───────────────────────────────────────────────────

    private func composeItemNotes(tags: [String], itemMetadata: FacetItemMetadata? = nil) -> String? {
        var metadata = itemMetadata ?? FacetItemMetadata()
        metadata.tags = tags
        return FacetMetadata.compose(userNotes: "", metadata: metadata.facetMetadata())
    }

    /// Delete a reminder and create a calendar event with the same content.
    /// Returns the new event identifier on success.
    @discardableResult
    func convertReminderToEvent(
        reminderId: String,
        project: String,
        content: String,
        tags: [String],
        itemMetadata: FacetItemMetadata? = nil,
        dueDate: Date?,
        durationMinutes: Int,
        calendarName: String,
        enabledCalendars: Set<String>? = nil
    ) async -> String? {
        let startDate = dueDate ?? Calendar.current.startOfDay(for: Date())
        let createdId = await createEvent(
            project: project,
            content: content,
            calendarName: calendarName,
            startDate: startDate,
            durationMinutes: max(durationMinutes, 15),
            tags: tags,
            itemMetadata: itemMetadata,
            enabledCalendars: enabledCalendars
        )
        guard let createdId else { return nil }
        return await deleteItem(id: reminderId) ? createdId : nil
    }

    /// Delete a calendar event and create a reminder with the same content.
    /// Returns the new reminder identifier on success.
    @discardableResult
    func convertEventToReminder(
        eventId: String,
        project: String,
        content: String,
        tags: [String],
        itemMetadata: FacetItemMetadata? = nil,
        priority: Int,
        startDate: Date?,
        hasTime: Bool,
        listName: String,
        enabledLists: Set<String>? = nil
    ) async -> String? {
        let newId = await createReminder(
            project: project,
            content: content,
            listName: listName,
            dueDate: startDate,
            dueIncludesTime: hasTime,
            tags: tags,
            itemMetadata: itemMetadata,
            priority: priority,
            enabledLists: enabledLists
        )
        guard let newId else { return nil }
        return await deleteItem(id: eventId) ? newId : nil
    }

    /// Delete an existing calendar item (reminder or event) by its identifier.
    func deleteItem(id: String) async -> Bool {
        guard let item = store.calendarItem(withIdentifier: id) else { return false }
        if let reminder = item as? EKReminder {
            do { try store.remove(reminder, commit: true); return true } catch { return false }
        } else if let event = item as? EKEvent {
            do { try store.remove(event, span: .thisEvent, commit: true); return true } catch { return false }
        }
        return false
    }

    // ── Week goal events ─────────────────────────────────────────────────────

    /// Create or update a week-spanning goal event. Returns the event identifier on success.
    func createOrUpdateGoalEvent(project: String, title: String, body: String,
                                  week: ISOWeek, calendarName: String?,
                                  existingEventId: String?,
                                  enabledCalendars: Set<String>? = nil) async -> String? {
        let startDate = week.startDate
        let endDate = week.endDate

        let calendars = filtered(store.calendars(for: .event), by: enabledCalendars)
        guard !calendars.isEmpty else { return nil }

        // Prefer the project's saved calendar, then the default, then any enabled calendar.
        let calendar = calendarForGoalEvent(named: calendarName, from: calendars)
        guard let calendar else { return nil }

        let event = goalEvent(
            project: project,
            week: week,
            existingEventId: existingEventId,
            enabledCalendars: calendars
        ) ?? EKEvent(eventStore: store)
        event.title = WeekGoalEvent.makeTitle(project: project, title: title)
        event.notes = WeekGoalEvent.makeNotes(body: body, project: project, weekID: week.id)
        event.isAllDay = true
        event.startDate = startDate
        event.endDate = endDate
        event.calendar = calendar

        do {
            try store.save(event, span: .thisEvent, commit: true)
            removeDuplicateGoalEvents(project: project, week: week, keeping: event, enabledCalendars: calendars)
            return event.calendarItemIdentifier
        } catch {
            return nil
        }
    }

    func weekGoalEvent(project: String, week: ISOWeek, existingEventId: String?,
                       enabledCalendars: Set<String>? = nil) async -> WeekGoalEventSnapshot? {
        let authorized = await MainActor.run { calendarAuthorized }
        guard authorized else { return nil }
        let calendars = filtered(store.calendars(for: .event), by: enabledCalendars)
        guard let event = goalEvent(project: project, week: week,
                                    existingEventId: existingEventId,
                                    enabledCalendars: calendars) else { return nil }
        return WeekGoalEventSnapshot(
            eventId: event.calendarItemIdentifier,
            title: ProjectPrefix.contentBody(of: event.title ?? ""),
            body: WeekGoalEvent.body(fromNotes: event.notes)
        )
    }

    private func calendarForGoalEvent(named name: String?, from calendars: [EKCalendar]) -> EKCalendar? {
        if let name,
           let cal = calendars.first(where: { $0.title == name }) {
            return cal
        }
        if let defaultCalendar = store.defaultCalendarForNewEvents {
            return calendars.first { $0.calendarIdentifier == defaultCalendar.calendarIdentifier }
                ?? calendars.first { $0.title == defaultCalendar.title }
        }
        return calendars.first
    }

    private func goalEvent(project: String, week: ISOWeek, existingEventId: String?,
                           enabledCalendars calendars: [EKCalendar]) -> EKEvent? {
        if let existingEventId,
           let event = store.calendarItem(withIdentifier: existingEventId) as? EKEvent,
           calendars.contains(where: { $0.calendarIdentifier == event.calendar.calendarIdentifier }),
           isGoalEvent(event, project: project, week: week) {
            return event
        }

        return goalEvents(project: project, week: week, enabledCalendars: calendars)
            .sorted { $0.startDate < $1.startDate }
            .first
    }

    private func goalEvents(project: String, week: ISOWeek, enabledCalendars calendars: [EKCalendar]) -> [EKEvent] {
        guard !calendars.isEmpty else { return [] }
        let pred = store.predicateForEvents(withStart: week.startDate, end: week.endDate, calendars: calendars)
        return store.events(matching: pred).filter { isGoalEvent($0, project: project, week: week) }
    }

    private func isGoalEvent(_ event: EKEvent, project: String, week: ISOWeek) -> Bool {
        let title = event.title ?? ""
        guard ProjectPrefix.projectName(of: title) == project else { return false }
        return WeekGoalEvent.hasGoalMetadata(event.notes, project: project, weekID: week.id)
    }

    private func removeDuplicateGoalEvents(project: String, week: ISOWeek, keeping keptEvent: EKEvent,
                                           enabledCalendars calendars: [EKCalendar]) {
        let duplicates = goalEvents(project: project, week: week, enabledCalendars: calendars).filter { event in
            event.calendarItemIdentifier != keptEvent.calendarItemIdentifier
        }
        for event in duplicates {
            try? store.remove(event, span: .thisEvent, commit: true)
        }
    }

    /// Delete a goal event by its identifier. Missing events are treated as already deleted.
    func deleteGoalEvent(eventId: String?) async -> Bool {
        guard let id = eventId else { return true }
        guard let event = store.calendarItem(withIdentifier: id) as? EKEvent else { return true }
        do {
            try store.remove(event, span: .thisEvent, commit: true)
            return true
        } catch {
            return false
        }
    }

    /// Update an existing item (reminder or event)'s content, date, container, metadata, and priority.
    ///
    /// `url` is only written when `updateURL` is true. Callers that don't edit the
    /// URL (inline title/notes edits, the edit sheet) leave it untouched — passing
    /// the default would otherwise silently erase an item's existing link.
    func updateItem(id: String, project: String, content: String,
                    date: Date?, useDate: Bool, dateIncludesTime: Bool,
                    containerName: String, tags: [String]? = nil, priority: Int,
                    url: URL? = nil, updateURL: Bool = false,
                    isAllDay: Bool? = nil, endDate: Date? = nil) async -> Bool {
        guard let item = store.calendarItem(withIdentifier: id) else { return false }

        let newTitle = ProjectPrefix.makeTitle(project: project, content: content)
        item.title = newTitle
        let existingMetadata = FacetMetadata.parse(notes: item.notes)
        var itemMetadata = FacetItemMetadata.parse(existingMetadata) ?? FacetItemMetadata()
        itemMetadata.tags = tags ?? existingMetadata.tags
        item.notes = FacetMetadata.compose(userNotes: "", metadata: itemMetadata.facetMetadata())
        if updateURL { item.url = url }

        if let reminder = item as? EKReminder {
            reminder.priority = priority
        }
        
        // Update container if it changed
        if item.calendar?.title != containerName {
            let entity: EKEntityType = (item is EKReminder) ? .reminder : .event
            if let newCal = store.calendars(for: entity).first(where: { $0.title == containerName }) {
                item.calendar = newCal
            }
        }
        
        if let reminder = item as? EKReminder {
            if useDate, let due = date {
                reminder.dueDateComponents = Self.reminderDueComponents(from: due, includesTime: dateIncludesTime)
            } else {
                reminder.dueDateComponents = nil
            }
            do { try store.save(reminder, commit: true); return true } catch { return false }
        } else if let event = item as? EKEvent {
            guard let start = date else { return false }
            let existingDuration = event.endDate.timeIntervalSince(event.startDate)

            if let allDay = isAllDay {
                event.isAllDay = allDay
            }

            if event.isAllDay {
                // All-day events: start at beginning of day, end = start + 1 day (exclusive)
                let cal = Calendar.current
                event.startDate = cal.startOfDay(for: start)
                if let end = endDate {
                    // Ensure end is at least start + 1 day
                    let minEnd = cal.date(byAdding: .day, value: 1, to: event.startDate)!
                    event.endDate = end < minEnd ? minEnd : cal.startOfDay(for: end)
                } else {
                    event.endDate = cal.date(byAdding: .day, value: 1, to: event.startDate)!
                }
            } else {
                // Timed events: use explicit endDate if provided, otherwise preserve duration
                event.startDate = start
                if let end = endDate {
                    event.endDate = end
                } else {
                    event.endDate = start.addingTimeInterval(existingDuration > 0 ? existingDuration : 3600)
                }
            }
            do { try store.save(event, span: .thisEvent, commit: true); return true } catch { return false }
        }
        return false
    }

    /// Replace a task/event notes field with canonical FacetX item metadata.
    /// The actual user note body should live in the local item note store.
    func rewriteItemMetadata(id: String, metadata itemMetadata: FacetItemMetadata) async -> Bool {
        guard let item = store.calendarItem(withIdentifier: id) else { return false }
        item.notes = FacetMetadata.compose(userNotes: "", metadata: itemMetadata.facetMetadata())

        do {
            if let reminder = item as? EKReminder {
                try store.save(reminder, commit: true)
                return true
            }
            if let event = item as? EKEvent {
                try store.save(event, span: .thisEvent, commit: true)
                return true
            }
            return false
        } catch {
            return false
        }
    }

    private static func hasReminderTime(_ components: DateComponents?) -> Bool {
        guard let components else { return false }
        return components.hour != nil || components.minute != nil || components.second != nil
    }

    private static var paperLinkScanStartDate: Date {
        Calendar.current.date(byAdding: .year, value: -50, to: Date()) ?? .distantPast
    }

    private static var paperLinkScanEndDate: Date {
        Calendar.current.date(byAdding: .year, value: 50, to: Date()) ?? .distantFuture
    }

    private static func reminderDueComponents(from date: Date, includesTime: Bool) -> DateComponents {
        let calendar = Calendar.current
        var components = calendar.dateComponents(
            includesTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day],
            from: date
        )
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        return components
    }
}
