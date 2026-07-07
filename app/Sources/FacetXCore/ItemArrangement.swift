import Foundation

public enum SortOption: String, CaseIterable, Identifiable, Sendable {
    case manual = "Manual"
    case priorityDesc = "Priority"
    case dateAsc = "Date"
    case dateDesc = "Date (newest)"
    case nameAsc = "Name"

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .manual: return "list.number"
        case .priorityDesc: return "flag.fill"
        case .dateAsc: return "calendar"
        case .dateDesc: return "calendar.badge.minus"
        case .nameAsc: return "textformat.abc"
        }
    }
}

public enum PlanSortOption: String, CaseIterable, Identifiable, Sendable {
    case manual = "Manual"
    case scheduleAsc = "Schedule"
    case priorityDesc = "Priority"
    case kindAsc = "Type"

    public var id: String { rawValue }
}

/// Pure ordering, grouping and date filtering for a project's items. Kept free
/// of SwiftUI and EventKit so it can be unit-checked in FacetXCoreChecks — these
/// are the rules most prone to silent regressions.
public enum ItemArrangement {

    /// A zone (container) and the items it holds, for the grouped list view.
    public struct ZoneGroup: Identifiable, Equatable {
        public let zone: String
        public let items: [ProjectItem]
        public var id: String { zone }
        public init(zone: String, items: [ProjectItem]) {
            self.zone = zone
            self.items = items
        }
    }

    /// Sort by the given option, falling back to arranged() defaults for ties.
    public static func sorted(_ items: [ProjectItem], by option: SortOption, savedOrder: [String] = []) -> [ProjectItem] {
        switch option {
        case .manual:
            return arranged(items, savedOrder: savedOrder)
        case .priorityDesc:
            // Apple semantics: 1=high … 9=low, 0=none. Map 0 to a sentinel so it sinks last.
            return items.sorted { a, b in
                if a.isCompleted != b.isCompleted { return !a.isCompleted }
                let pa = a.priority == 0 ? Int.max : a.priority
                let pb = b.priority == 0 ? Int.max : b.priority
                if pa != pb { return pa < pb }
                return (a.date ?? .distantFuture) < (b.date ?? .distantFuture)
            }
        case .dateAsc:
            return byDate(items)
        case .dateDesc:
            return items.sorted { a, b in
                if a.isCompleted != b.isCompleted { return !a.isCompleted }
                return (a.date ?? .distantPast) > (b.date ?? .distantPast)
            }
        case .nameAsc:
            return items.sorted { a, b in
                if a.isCompleted != b.isCompleted { return !a.isCompleted }
                let cmp = a.content.localizedStandardCompare(b.content)
                if cmp != .orderedSame { return cmp == .orderedAscending }
                return (a.date ?? .distantFuture) < (b.date ?? .distantFuture)
            }
        }
    }

    public static func sorted(_ items: [ProjectItem], by option: PlanSortOption, savedOrder: [String] = []) -> [ProjectItem] {
        switch option {
        case .manual:
            return arranged(items, savedOrder: savedOrder)
        case .scheduleAsc:
            return items.sorted(by: planScheduleComparator(savedOrder: savedOrder))
        case .priorityDesc:
            return items.sorted(by: priorityComparator(savedOrder: savedOrder))
        case .kindAsc:
            return items.sorted(by: kindComparator(savedOrder: savedOrder))
        }
    }

    /// The all-items order: incomplete before completed, then the project's saved
    /// manual order, then earliest date as a tiebreaker. Undated items sort last.
    public static func arranged(_ items: [ProjectItem], savedOrder: [String]) -> [ProjectItem] {
        // Precompute id → rank so each comparison is O(1) instead of scanning
        // savedOrder, keeping the overall sort at O(n log n).
        var rank = [String: Int](minimumCapacity: savedOrder.count)
        for (i, id) in savedOrder.enumerated() { rank[id] = i }
        return items.sorted { a, b in
            if a.isCompleted != b.isCompleted { return !a.isCompleted }
            let ra = rank[a.id] ?? Int.max
            let rb = rank[b.id] ?? Int.max
            if ra == rb { return (a.date ?? .distantFuture) < (b.date ?? .distantFuture) }
            return ra < rb
        }
    }

    /// Incomplete before completed, then earliest date. Used by date-scoped views.
    public static func byDate(_ items: [ProjectItem]) -> [ProjectItem] {
        items.sorted { a, b in
            if a.isCompleted != b.isCompleted { return !a.isCompleted }
            return (a.date ?? .distantFuture) < (b.date ?? .distantFuture)
        }
    }

    /// Group items by container, preserving each item's incoming order within a
    /// group and sorting the groups by zone name. Pass already-arranged items so
    /// the per-group order is meaningful.
    public static func groupedByZone(_ items: [ProjectItem]) -> [ZoneGroup] {
        Dictionary(grouping: items, by: \.containerName)
            .map { ZoneGroup(zone: $0.key, items: $0.value) }
            .sorted { $0.zone < $1.zone }
    }

    /// The subset of items whose date falls within `week`, ordered by date.
    public static func inWeek(_ items: [ProjectItem], _ week: ISOWeek) -> [ProjectItem] {
        byDate(items.filter { item in
            guard let d = item.date else { return false }
            return week.contains(d)
        })
    }

    /// The subset of items whose date falls within `month`, ordered by date.
    public static func inMonth(_ items: [ProjectItem], _ month: MonthYear) -> [ProjectItem] {
        byDate(items.filter { item in
            guard let d = item.date else { return false }
            return month.contains(d)
        })
    }

    private static func completionRank(_ item: ProjectItem) -> Int {
        item.isCompleted ? 1 : 0
    }

    private static func manualRanks(_ savedOrder: [String]) -> [String: Int] {
        var rank = [String: Int](minimumCapacity: savedOrder.count)
        for (index, id) in savedOrder.enumerated() { rank[id] = index }
        return rank
    }

    private static func manualRank(_ item: ProjectItem, ranks: [String: Int]) -> Int {
        ranks[item.id] ?? Int.max
    }

    private static func priorityRank(_ item: ProjectItem) -> Int {
        item.priority == 0 ? Int.max : item.priority
    }

    private static func kindRank(_ item: ProjectItem) -> Int {
        switch item.kind {
        case .event: return 0
        case .reminder: return 1
        }
    }

    private static func compareFallback(_ a: ProjectItem, _ b: ProjectItem, ranks: [String: Int]) -> Bool {
        let ra = manualRank(a, ranks: ranks)
        let rb = manualRank(b, ranks: ranks)
        if ra != rb { return ra < rb }
        let cmp = a.content.localizedStandardCompare(b.content)
        if cmp != .orderedSame { return cmp == .orderedAscending }
        return a.id < b.id
    }

    private static func planScheduleComparator(savedOrder: [String]) -> (ProjectItem, ProjectItem) -> Bool {
        let ranks = manualRanks(savedOrder)
        return { a, b in
            let ca = completionRank(a)
            let cb = completionRank(b)
            if ca != cb { return ca < cb }
            let da = a.date ?? .distantFuture
            let db = b.date ?? .distantFuture
            if da != db { return da < db }
            if a.hasTime != b.hasTime { return a.hasTime && !b.hasTime }
            if a.isAllDay != b.isAllDay { return !a.isAllDay && b.isAllDay }
            return compareFallback(a, b, ranks: ranks)
        }
    }

    private static func priorityComparator(savedOrder: [String]) -> (ProjectItem, ProjectItem) -> Bool {
        let ranks = manualRanks(savedOrder)
        return { a, b in
            let ca = completionRank(a)
            let cb = completionRank(b)
            if ca != cb { return ca < cb }
            let pa = priorityRank(a)
            let pb = priorityRank(b)
            if pa != pb { return pa < pb }
            let da = a.date ?? .distantFuture
            let db = b.date ?? .distantFuture
            if da != db { return da < db }
            return compareFallback(a, b, ranks: ranks)
        }
    }

    private static func kindComparator(savedOrder: [String]) -> (ProjectItem, ProjectItem) -> Bool {
        let ranks = manualRanks(savedOrder)
        return { a, b in
            let ca = completionRank(a)
            let cb = completionRank(b)
            if ca != cb { return ca < cb }
            let ka = kindRank(a)
            let kb = kindRank(b)
            if ka != kb { return ka < kb }
            let da = a.date ?? .distantFuture
            let db = b.date ?? .distantFuture
            if da != db { return da < db }
            return compareFallback(a, b, ranks: ranks)
        }
    }

}
