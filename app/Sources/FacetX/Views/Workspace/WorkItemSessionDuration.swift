import FacetXCore
import Foundation

enum WorkItemSessionDuration {
    static func defaultMinutes(
        for item: WorkItem,
        eventDefaultMinutes: Int,
        treatsAllDayEventsAsTimed: Bool = false
    ) -> Int? {
        switch item.kind {
        case .reminder:
            return nil
        case .event:
            guard treatsAllDayEventsAsTimed || !item.isAllDay else { return nil }
            return explicitMinutes(for: item) ?? max(eventDefaultMinutes, 15)
        }
    }

    static func hours(
        for item: WorkItem,
        eventDefaultMinutes: Int,
        treatsAllDayEventsAsTimed: Bool = false
    ) -> Double {
        guard let minutes = defaultMinutes(
            for: item,
            eventDefaultMinutes: eventDefaultMinutes,
            treatsAllDayEventsAsTimed: treatsAllDayEventsAsTimed
        ) else {
            return 0.33
        }
        return Double(minutes) / 60.0
    }

    static func endDate(
        for item: WorkItem,
        start: Date,
        eventDefaultMinutes: Int,
        treatsAllDayEventsAsTimed: Bool = false,
        calendar: Calendar = .current
    ) -> Date? {
        guard let minutes = defaultMinutes(
            for: item,
            eventDefaultMinutes: eventDefaultMinutes,
            treatsAllDayEventsAsTimed: treatsAllDayEventsAsTimed
        ) else {
            return nil
        }
        return calendar.date(byAdding: .minute, value: minutes, to: start)
    }

    private static func explicitMinutes(for item: WorkItem) -> Int? {
        guard !item.isAllDay, let start = item.date, let end = item.endDate, end > start else {
            return nil
        }
        return max(Int((end.timeIntervalSince(start) / 60).rounded()), 15)
    }
}
