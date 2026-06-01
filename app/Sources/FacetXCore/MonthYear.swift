import Foundation

/// Month-level date utilities. A month is identified as "2026-06" and runs
/// from the 1st to the last day, with weeks starting on Monday.
public struct MonthYear: Equatable {
    public var year: Int
    public var month: Int

    public init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    public static var calendar: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.firstWeekday = 2
        return c
    }

    public static func containing(_ date: Date) -> MonthYear {
        let c = calendar.dateComponents([.year, .month], from: date)
        return MonthYear(year: c.year ?? 0, month: c.month ?? 1)
    }

    public var id: String { String(format: "%04d-%02d", year, month) }

    /// First day of the month at 00:00.
    public var startDate: Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        return MonthYear.calendar.date(from: comps) ?? Date()
    }

    /// The instant just after the last day of the month (exclusive end).
    public var endDate: Date {
        MonthYear.calendar.date(byAdding: .month, value: 1, to: startDate) ?? Date()
    }

    public var numberOfDays: Int {
        MonthYear.calendar.range(of: .day, in: .month, for: startDate)?.count ?? 30
    }

    /// Offset of the first day from Monday (0 = Monday, 6 = Sunday).
    public var firstWeekdayOffset: Int {
        let weekday = MonthYear.calendar.component(.weekday, from: startDate)
        // Sunday=1 -> 6, Monday=2 -> 0, Tuesday=3 -> 1, ...
        return (weekday + 5) % 7
    }

    public func shifted(by months: Int) -> MonthYear {
        let d = MonthYear.calendar.date(byAdding: .month, value: months, to: startDate) ?? startDate
        return MonthYear.containing(d)
    }

    public func contains(_ date: Date) -> Bool {
        date >= startDate && date < endDate
    }

    /// Human label, e.g. "June 2026".
    public var label: String {
        let df = DateFormatter()
        df.dateFormat = "MMMM yyyy"
        return df.string(from: startDate)
    }

    public func isToday(day: Int) -> Bool {
        guard let date = dateForDay(day) else { return false }
        let today = MonthYear.calendar.startOfDay(for: Date())
        let cellDay = MonthYear.calendar.startOfDay(for: date)
        return today == cellDay
    }

    public func dateForDay(_ day: Int) -> Date? {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        return MonthYear.calendar.date(from: comps)
    }
}
