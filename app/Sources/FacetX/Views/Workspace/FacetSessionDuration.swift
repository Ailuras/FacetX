import FacetXCore
import Foundation

enum FacetSessionDuration {
    static func defaultMinutes(
        for item: ProjectItem,
        eventDefaultMinutes: Int,
        paperDefaultMinutes: Int,
        noteDefaultMinutes: Int,
        treatsAllDayEventsAsTimed: Bool = false
    ) -> Int? {
        switch item.facetKind {
        case .task:
            return nil
        case .event:
            guard treatsAllDayEventsAsTimed || !item.isAllDay else { return nil }
            return explicitMinutes(for: item) ?? max(eventDefaultMinutes, 15)
        case .paper:
            return max(paperDefaultMinutes, 15)
        case .note:
            return explicitMinutes(for: item) ?? max(noteDefaultMinutes, 15)
        }
    }

    static func hours(
        for item: ProjectItem,
        eventDefaultMinutes: Int,
        paperDefaultMinutes: Int,
        noteDefaultMinutes: Int,
        treatsAllDayEventsAsTimed: Bool = false
    ) -> Double {
        guard let minutes = defaultMinutes(
            for: item,
            eventDefaultMinutes: eventDefaultMinutes,
            paperDefaultMinutes: paperDefaultMinutes,
            noteDefaultMinutes: noteDefaultMinutes,
            treatsAllDayEventsAsTimed: treatsAllDayEventsAsTimed
        ) else {
            return 0.33
        }
        return Double(minutes) / 60.0
    }

    static func endDate(
        for item: ProjectItem,
        start: Date,
        eventDefaultMinutes: Int,
        paperDefaultMinutes: Int,
        noteDefaultMinutes: Int,
        treatsAllDayEventsAsTimed: Bool = false,
        calendar: Calendar = .current
    ) -> Date? {
        guard let minutes = defaultMinutes(
            for: item,
            eventDefaultMinutes: eventDefaultMinutes,
            paperDefaultMinutes: paperDefaultMinutes,
            noteDefaultMinutes: noteDefaultMinutes,
            treatsAllDayEventsAsTimed: treatsAllDayEventsAsTimed
        ) else {
            return nil
        }
        return calendar.date(byAdding: .minute, value: minutes, to: start)
    }

    private static func explicitMinutes(for item: ProjectItem) -> Int? {
        guard !item.isAllDay, let start = item.date, let end = item.endDate, end > start else {
            return nil
        }
        return max(Int((end.timeIntervalSince(start) / 60).rounded()), 15)
    }
}
