import Foundation

public enum ItemKindScope: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case tasks = "Tasks"
    case events = "Events"
    case papers = "Papers"
    case notes = "Notes"

    public var id: String { rawValue }

    public func matches(_ facetKind: FacetKind) -> Bool {
        switch self {
        case .all:
            return true
        case .tasks:
            return facetKind == .task
        case .events:
            return facetKind == .event
        case .papers:
            return facetKind == .paper
        case .notes:
            return facetKind == .note
        }
    }
}

public enum ItemDateScope: String, CaseIterable, Identifiable, Sendable {
    case all = "Any Time"
    case today = "Today"
    case nextSevenDays = "Next 7 Days"

    public var id: String { rawValue }

    public func matches(_ date: Date?, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        switch self {
        case .all:
            return true
        case .today:
            guard let date else { return false }
            return calendar.isDate(date, inSameDayAs: now)
        case .nextSevenDays:
            guard let date else { return false }
            let start = calendar.startOfDay(for: now)
            guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return false }
            return date >= start && date < end
        }
    }
}

public struct ItemListFilter: Equatable, Sendable {
    public var kindScope: ItemKindScope
    public var dateScope: ItemDateScope

    public init(kindScope: ItemKindScope = .all, dateScope: ItemDateScope = .all) {
        self.kindScope = kindScope
        self.dateScope = dateScope
    }

    public var isActive: Bool {
        kindScope != .all || dateScope != .all
    }

    public func matches(_ item: ProjectItem, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        kindScope.matches(item.facetKind) && dateScope.matches(item.date, now: now, calendar: calendar)
    }
}
