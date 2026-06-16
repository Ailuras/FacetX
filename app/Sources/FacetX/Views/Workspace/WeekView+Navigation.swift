import FacetXCore
import SwiftUI

extension WeekView {
    var weekNav: some View {
        PeriodNavigationBar(
            title: L10n.language == "zh" ? "第 \(week.week) 周" : "Week \(week.week)",
            subtitle: weekRangeLabel,
            previousHelp: L10n.t(.prevWeek),
            nextHelp: L10n.t(.nextWeek),
            currentHelp: L10n.t(.currentWeek),
            onPrevious: { week = week.shifted(by: -1) },
            onNext: { week = week.shifted(by: 1) },
            onCurrent: { week = ISOWeek.containing(Date()) }
        ) {
            if hasActiveSearch {
                FacetInfoBadge(
                    text: "\(weekItems.count) \(L10n.t(.resultsUnit))",
                    systemImage: "magnifyingglass",
                    tint: .secondary,
                    fill: Color.accentColor.opacity(0.08)
                )
            }
            if !showCompleted && hiddenReminderCount > 0 {
                FacetInfoBadge(
                    text: "\(hiddenReminderCount) \(L10n.t(.hiddenUnit))",
                    systemImage: "eye.slash",
                    tint: .secondary,
                    fill: Color.orange.opacity(0.08)
                )
            }
            if !tagFilter.isEmpty {
                ActiveTagFilterBar(tagFilter: $tagFilter)
            }
            if itemFilter.isActive {
                FacetInfoBadge(
                    text: "\(weekItems.count) \(L10n.t(.shownUnit))",
                    systemImage: "line.3.horizontal.decrease.circle",
                    tint: .secondary,
                    fill: Color.accentColor.opacity(0.08)
                )
            }
            ItemActionCluster(itemFilter: $itemFilter, showCompleted: $showCompleted, animation: listAnimation) {
                onCreateItem(week.startDate)
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
