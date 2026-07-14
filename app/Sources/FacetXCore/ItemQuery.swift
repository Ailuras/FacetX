import Foundation

public struct ItemCounts: Equatable, Sendable {
    public let taskOpenCount: Int
    public let taskCompletedCount: Int
    public let eventCount: Int

    public init(taskOpenCount: Int, taskCompletedCount: Int, eventCount: Int) {
        self.taskOpenCount = taskOpenCount
        self.taskCompletedCount = taskCompletedCount
        self.eventCount = eventCount
    }

    /// Total across every element type (open + completed tasks included).
    public var allCount: Int {
        taskOpenCount + taskCompletedCount + eventCount
    }
}

public enum ItemQuery {
    public static func searched(_ items: [WorkItem], query: String) -> [WorkItem] {
        items.filter { $0.matches(searchQuery: query) }
    }

    public static func completedVisibility(_ items: [WorkItem], showCompleted: Bool) -> [WorkItem] {
        guard !showCompleted else { return items }
        return items.filter { !$0.isCompleted }
    }

    /// Hides overdue (past-due, still-open) items when `showOverdue` is false, so
    /// the list can focus on what's upcoming. Mirrors `completedVisibility`.
    public static func overdueVisibility(_ items: [WorkItem], showOverdue: Bool) -> [WorkItem] {
        guard !showOverdue else { return items }
        return items.filter { !$0.isOverdue }
    }

    public static func filtered(_ items: [WorkItem], by tagFilter: TagFilter) -> [WorkItem] {
        guard !tagFilter.isEmpty else { return items }
        return items.filter { tagFilter.matches($0) }
    }

    public static func filtered(
        _ items: [WorkItem],
        by itemFilter: ItemListFilter,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [WorkItem] {
        guard itemFilter.isActive else { return items }
        return items.filter { itemFilter.matches($0, now: now, calendar: calendar) }
    }

    public static func todayItems(
        _ items: [WorkItem],
        calendar: Calendar = .current,
        includeCompletedReminders: Bool = false
    ) -> [WorkItem] {
        items.filter { item in
            guard let date = item.date else { return false }
            if !includeCompletedReminders, item.kind == .reminder, item.isCompleted {
                return false
            }
            return calendar.isDateInToday(date)
        }
    }

    public static func counts(for items: [WorkItem]) -> ItemCounts {
        ItemCounts(
            taskOpenCount: items.filter { $0.kind == .reminder && !$0.isCompleted }.count,
            taskCompletedCount: items.filter { $0.kind == .reminder && $0.isCompleted }.count,
            eventCount: items.filter { $0.kind == .event }.count
        )
    }

    public static func workPrefixCount(for items: [WorkItem]) -> Int {
        Set(items.map(\.workPrefix)).count
    }
}
