import Combine
import FacetXCore
import Foundation

/// Shared data source for the desktop widget and the menu bar badge.
///
/// Fetches every active work's items once and derives today/overdue/goal
/// slices from that single snapshot, refreshing on EventKit changes, settings
/// changes, work edits, and a minute tick (so "today" and overdue states
/// roll over without user interaction).
@MainActor
final class WidgetDataModel: ObservableObject {
    @Published private(set) var items: [WorkItem] = []
    @Published private(set) var lastRefreshed: Date?

    private weak var eventKit: EventKitService?
    private weak var store: WorkStore?
    private weak var settings: AppSettings?
    private var cancellables: Set<AnyCancellable> = []
    private var configured = false

    func configure(eventKit: EventKitService, store: WorkStore, settings: AppSettings) {
        guard !configured else { return }
        configured = true
        self.eventKit = eventKit
        self.store = store
        self.settings = settings

        eventKit.$changeToken
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleReload() }
            .store(in: &cancellables)

        settings.$changeToken
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleReload() }
            .store(in: &cancellables)

        store.$works
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleReload() }
            .store(in: &cancellables)

        Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.scheduleReload() }
            .store(in: &cancellables)

        scheduleReload()
    }

    func scheduleReload() {
        Task { await reload() }
    }

    func reload() async {
        guard let eventKit, let store, let settings else { return }
        let prefixes = Set(store.activeWorks.map(\.prefix))
        let fetched = await eventKit.items(
            forWorks: prefixes,
            enabledReminderLists: settings.effectiveReminderListNames,
            enabledCalendars: settings.effectiveCalendarNames
        )
        items = fetched
        lastRefreshed = Date()
    }

    /// Toggle a reminder's completion, optimistically flipping the local
    /// snapshot so the widget responds instantly; EventKit's change token then
    /// reconciles through the normal reload path.
    func setCompleted(_ completed: Bool, item: WorkItem) {
        guard item.kind == .reminder, let eventKit else { return }
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx] = item.applyingLocalState(isPinned: item.isPinned, isCompleted: completed)
        }
        Task { await eventKit.setReminderCompleted(id: item.id, completed: completed) }
    }

    // ── Derived slices ───────────────────────────────────────────────────────

    /// Everything happening today (open reminders due today + today's events),
    /// timed items sorted by time, untimed/all-day first.
    var todayItems: [WorkItem] {
        ItemQuery.todayItems(items, includeCompletedReminders: true)
            .sorted { a, b in
                let aTimed = a.hasTime && !a.isAllDay
                let bTimed = b.hasTime && !b.isAllDay
                if aTimed != bTimed { return !aTimed }
                guard let da = a.date, let db = b.date else { return a.content < b.content }
                if da != db { return da < db }
                return a.content < b.content
            }
    }

    /// Open reminders whose due date is in the past (before today).
    var overdueItems: [WorkItem] {
        items.filter { $0.isOverdue && !Calendar.current.isDateInToday($0.date ?? .distantPast) }
            .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }

    var todayOpenCount: Int {
        todayItems.filter { $0.kind == .reminder && !$0.isCompleted }.count
    }

    var todayDoneCount: Int {
        todayItems.filter { $0.kind == .reminder && $0.isCompleted }.count
    }

    var todayEventCount: Int {
        todayItems.filter { $0.kind == .event }.count
    }

    /// Today's completion progress across reminders (0…1); nil when there is
    /// nothing due today, so the ring can show an idle state.
    var todayProgress: Double? {
        let total = todayOpenCount + todayDoneCount
        guard total > 0 else { return nil }
        return Double(todayDoneCount) / Double(total)
    }

    /// The badge shown next to the menu bar icon: what still needs attention
    /// today (open reminders due today + overdue).
    var menuBarBadgeCount: Int {
        todayOpenCount + overdueItems.count
    }

    /// Current-week goals across active works, in sidebar order.
    var currentWeekGoals: [(work: Work, goal: WeekGoal)] {
        guard let store else { return [] }
        let weekId = ISOWeek.containing(Date()).id
        return store.activeWorks.compactMap { work in
            work.weekGoals.first { $0.weekId == weekId }.map { (work, $0) }
        }
    }
}
