import Foundation

public struct ItemCounts: Equatable, Sendable {
    public let taskOpenCount: Int
    public let taskCompletedCount: Int
    public let eventCount: Int
    public let paperCount: Int
    public let noteCount: Int

    public init(taskOpenCount: Int, taskCompletedCount: Int, eventCount: Int, paperCount: Int, noteCount: Int) {
        self.taskOpenCount = taskOpenCount
        self.taskCompletedCount = taskCompletedCount
        self.eventCount = eventCount
        self.paperCount = paperCount
        self.noteCount = noteCount
    }

    /// Total across every element type (open + completed tasks included).
    public var allCount: Int {
        taskOpenCount + taskCompletedCount + eventCount + paperCount + noteCount
    }
}

public enum ItemQuery {
    public static func searched(_ items: [ProjectItem], query: String) -> [ProjectItem] {
        items.filter { $0.matches(searchQuery: query) }
    }

    public static func completedVisibility(_ items: [ProjectItem], showCompleted: Bool) -> [ProjectItem] {
        guard !showCompleted else { return items }
        return items.filter { !($0.kind == .reminder && $0.isCompleted) }
    }

    public static func filtered(_ items: [ProjectItem], by tagFilter: TagFilter) -> [ProjectItem] {
        guard !tagFilter.isEmpty else { return items }
        return items.filter { tagFilter.matches($0) }
    }

    public static func filtered(
        _ items: [ProjectItem],
        by itemFilter: ItemListFilter,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ProjectItem] {
        guard itemFilter.isActive else { return items }
        return items.filter { itemFilter.matches($0, now: now, calendar: calendar) }
    }

    public static func todayItems(
        _ items: [ProjectItem],
        calendar: Calendar = .current,
        includeCompletedReminders: Bool = false
    ) -> [ProjectItem] {
        items.filter { item in
            guard let date = item.date else { return false }
            if !includeCompletedReminders, item.kind == .reminder, item.isCompleted {
                return false
            }
            return calendar.isDateInToday(date)
        }
    }

    public static func counts(for items: [ProjectItem]) -> ItemCounts {
        ItemCounts(
            taskOpenCount: items.filter { $0.facetKind == .task && !$0.isCompleted }.count,
            taskCompletedCount: items.filter { $0.facetKind == .task && $0.isCompleted }.count,
            eventCount: items.filter { $0.facetKind == .event }.count,
            paperCount: items.filter { $0.facetKind == .paper }.count,
            noteCount: items.filter { $0.facetKind == .note }.count
        )
    }

    public static func projectPrefixCount(for items: [ProjectItem]) -> Int {
        Set(items.map(\.projectPrefix)).count
    }
}
