import EventKit
import Foundation

/// A reminder or calendar event, flattened for the UI and tagged with the
/// project it belongs to (via the title prefix).
struct ProjectItem: Identifiable, Hashable {
    enum Kind { case reminder, event }
    let id: String          // EventKit calendarItemIdentifier / eventIdentifier
    let kind: Kind
    let rawTitle: String
    let content: String     // title with the project prefix stripped
    let containerName: String   // reminder list / calendar = functional zone
    let isCompleted: Bool
    let date: Date?         // due date (reminder) or start date (event)
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

    func requestAccess() async {
        let reminders = (try? await store.requestFullAccessToReminders()) ?? false
        let calendar = (try? await store.requestFullAccessToEvents()) ?? false
        await MainActor.run {
            self.remindersAuthorized = reminders
            self.calendarAuthorized = calendar
        }
    }

    /// All items (reminders + events) whose title prefix matches `project`.
    func items(forProject project: String,
               eventWindowDays: Int = 120) async -> [ProjectItem] {
        let (rem, cal) = await MainActor.run { (remindersAuthorized, calendarAuthorized) }
        var result: [ProjectItem] = []
        if rem { result += await reminders(forProject: project) }
        if cal { result += events(forProject: project, windowDays: eventWindowDays) }
        return result.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }

    /// Distinct project names discovered across all reminders + recent events.
    func discoverProjectNames(eventWindowDays: Int = 120) async -> [String] {
        let (rem, cal) = await MainActor.run { (remindersAuthorized, calendarAuthorized) }
        var names = Set<String>()
        if rem {
            // Map to project names inside the callback; EKReminder is not Sendable.
            let discovered = await fetchReminderProjectNames()
            names.formUnion(discovered)
        }
        if cal {
            for e in recentEvents(windowDays: eventWindowDays) {
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
    private func reminders(forProject project: String) async -> [ProjectItem] {
        let lists = store.calendars(for: .reminder)
        let pred = store.predicateForReminders(in: lists)
        return await withCheckedContinuation { cont in
            store.fetchReminders(matching: pred) { reminders in
                let items = (reminders ?? []).compactMap { r -> ProjectItem? in
                    let title = r.title ?? ""
                    guard ProjectPrefix.belongs(title: title, toProject: project) else { return nil }
                    return ProjectItem(
                        id: r.calendarItemIdentifier,
                        kind: .reminder,
                        rawTitle: title,
                        content: ProjectPrefix.contentBody(of: title),
                        containerName: r.calendar?.title ?? "?",
                        isCompleted: r.isCompleted,
                        date: r.dueDateComponents?.date
                    )
                }
                cont.resume(returning: items)
            }
        }
    }

    private func fetchReminderProjectNames() async -> Set<String> {
        let lists = store.calendars(for: .reminder)
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

    private func events(forProject project: String, windowDays: Int) -> [ProjectItem] {
        recentEvents(windowDays: windowDays).compactMap { e in
            let title = e.title ?? ""
            guard ProjectPrefix.belongs(title: title, toProject: project) else { return nil }
            return ProjectItem(
                id: e.eventIdentifier ?? UUID().uuidString,
                kind: .event,
                rawTitle: title,
                content: ProjectPrefix.contentBody(of: title),
                containerName: e.calendar.title,
                isCompleted: false,
                date: e.startDate
            )
        }
    }

    private func recentEvents(windowDays: Int) -> [EKEvent] {
        let cals = store.calendars(for: .event)
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -windowDays, to: now)!
        let end = Calendar.current.date(byAdding: .day, value: windowDays, to: now)!
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: cals)
        return store.events(matching: pred)
    }

    // ── Write-back ───────────────────────────────────────────────────────────

    /// Toggle a reminder's completion by its identifier.
    func setReminderCompleted(id: String, completed: Bool) async {
        guard let item = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        item.isCompleted = completed
        try? store.save(item, commit: true)
    }
}
