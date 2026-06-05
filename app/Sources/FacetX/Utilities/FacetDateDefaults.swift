import Foundation

enum FacetDateDefaults {
    static func dayDefault(reference: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: reference)
    }

    static func nextWholeHour(reference: Date = Date(), calendar: Calendar = .current) -> Date {
        let currentHour = calendar.dateInterval(of: .hour, for: reference)?.start ?? reference
        return calendar.date(byAdding: .hour, value: 1, to: currentHour) ?? reference
    }

    static func nextWholeHour(on day: Date, reference: Date = Date(), calendar: Calendar = .current) -> Date {
        let next = nextWholeHour(reference: reference, calendar: calendar)
        var dayComponents = calendar.dateComponents([.year, .month, .day], from: day)
        dayComponents.hour = calendar.component(.hour, from: next)
        dayComponents.minute = 0
        dayComponents.second = 0
        dayComponents.nanosecond = 0
        return calendar.date(from: dayComponents) ?? next
    }
}
