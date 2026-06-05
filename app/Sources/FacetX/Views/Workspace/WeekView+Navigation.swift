import FacetXCore
import SwiftUI

extension WeekView {
    var weekNav: some View {
        PeriodNavigationBar(
            title: "Week \(week.week)",
            subtitle: weekRangeLabel,
            previousHelp: "Previous week",
            nextHelp: "Next week",
            currentHelp: "Go to current week",
            onPrevious: { week = week.shifted(by: -1) },
            onNext: { week = week.shifted(by: 1) },
            onCurrent: { week = ISOWeek.containing(Date()) }
        ) {
            if hasActiveSearch {
                FacetInfoBadge(
                    text: "\(weekItems.count) results",
                    systemImage: "magnifyingglass",
                    tint: .secondary,
                    fill: Color.accentColor.opacity(0.08)
                )
            }
        }
    }

    var weekRangeLabel: String {
        let start = week.startDate
        let end = Calendar(identifier: .iso8601).date(byAdding: .day, value: 6, to: start) ?? start
        let startFormatter = DateFormatter()
        startFormatter.dateFormat = Calendar.current.isDate(start, equalTo: end, toGranularity: .year) ? "MMM d" : "MMM d, yyyy"
        let endFormatter = DateFormatter()
        endFormatter.dateFormat = "MMM d, yyyy"
        return "\(startFormatter.string(from: start)) - \(endFormatter.string(from: end))"
    }

}
