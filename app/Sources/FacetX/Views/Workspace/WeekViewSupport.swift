import FacetXCore
import SwiftUI

struct DayGroup: Identifiable {
    let date: Date
    let label: String
    let weekdayLabel: String
    let items: [ProjectItem]
    let isToday: Bool

    var id: Date { date }
    var scheduleItems: [ProjectItem] { items.filter { $0.kind == .event } }
    var taskItems: [ProjectItem] { items.filter { $0.kind == .reminder } }
}

struct DateWrapper: Identifiable {
    let date: Date

    var id: TimeInterval { date.timeIntervalSinceReferenceDate }
}

extension View {
    func goalCard(accented: Bool) -> some View {
        self
            .padding(14)
            .background(accented ? FacetTheme.softAccent : FacetTheme.quietPanel)
            .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                    .stroke(accented ? Color.accentColor.opacity(0.22) : FacetTheme.hairline, lineWidth: 1)
            )
    }
}
