import FacetXCore
import SwiftUI

extension WeekView {
    var weekNav: some View {
        HStack {
            Button { week = week.shifted(by: -1) } label: { Image(systemName: "chevron.left") }
                .help("Previous week")
            Spacer()
            VStack(spacing: 2) {
                Text("Week \(week.week)").font(.headline)
                Text(weekRangeLabel).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button { week = week.shifted(by: 1) } label: { Image(systemName: "chevron.right") }
                .help("Next week")
            Button("Current week") { week = ISOWeek.containing(Date()) }
                .font(.caption)
                .help("Go to current week")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(FacetTheme.canvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(FacetTheme.hairline).frame(height: 1)
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
