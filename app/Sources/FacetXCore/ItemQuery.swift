import Foundation

public struct ItemCounts: Equatable, Sendable {
    public let openReminderCount: Int
    public let completedReminderCount: Int
    public let eventCount: Int
    public let literatureCount: Int

    public init(openReminderCount: Int, completedReminderCount: Int, eventCount: Int, literatureCount: Int) {
        self.openReminderCount = openReminderCount
        self.completedReminderCount = completedReminderCount
        self.eventCount = eventCount
        self.literatureCount = literatureCount
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
            openReminderCount: items.filter { $0.kind == .reminder && !$0.isCompleted }.count,
            completedReminderCount: items.filter { $0.kind == .reminder && $0.isCompleted }.count,
            eventCount: items.filter { $0.kind == .event && $0.linkedPaperIDs.isEmpty }.count,
            literatureCount: items.filter { $0.kind == .event && !$0.linkedPaperIDs.isEmpty }.count
        )
    }

    public static func projectPrefixCount(for items: [ProjectItem]) -> Int {
        Set(items.map(\.projectPrefix)).count
    }
}
