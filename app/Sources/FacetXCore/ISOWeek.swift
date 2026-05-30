import Foundation

/// ISO-8601 week utilities. A week is identified as "2026-W22" and runs
/// Monday-Sunday.
public struct ISOWeek: Equatable {
    public var year: Int
    public var week: Int

    public init(year: Int, week: Int) {
        self.year = year
        self.week = week
    }

    private static var cal: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.firstWeekday = 2
        return c
    }

    public static func containing(_ date: Date) -> ISOWeek {
        let c = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return ISOWeek(year: c.yearForWeekOfYear ?? 0, week: c.weekOfYear ?? 0)
    }

    public var id: String { String(format: "%04d-W%02d", year, week) }

    /// Monday 00:00 of this week.
    public var startDate: Date {
        var comps = DateComponents()
        comps.yearForWeekOfYear = year
        comps.weekOfYear = week
        comps.weekday = 2
        return ISOWeek.cal.date(from: comps) ?? Date()
    }

    /// The instant just after Sunday 23:59:59 (exclusive end).
    public var endDate: Date {
        ISOWeek.cal.date(byAdding: .day, value: 7, to: startDate) ?? Date()
    }

    public func shifted(by weeks: Int) -> ISOWeek {
        let d = ISOWeek.cal.date(byAdding: .weekOfYear, value: weeks, to: startDate) ?? startDate
        return ISOWeek.containing(d)
    }

    public func contains(_ date: Date) -> Bool {
        date >= startDate && date < endDate
    }

    /// Human label, e.g. "Week 22 · May 25 – 31".
    public var label: String {
        let start = startDate
        let end = ISOWeek.cal.date(byAdding: .day, value: 6, to: start) ?? start
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        let endDf = DateFormatter()
        endDf.dateFormat = Calendar.current.isDate(start, equalTo: end, toGranularity: .month)
            ? "d" : "MMM d"
        return "Week \(week) · \(df.string(from: start)) – \(endDf.string(from: end))"
    }
}
