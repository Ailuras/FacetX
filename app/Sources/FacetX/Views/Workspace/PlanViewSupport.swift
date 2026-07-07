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

struct PlanDayLoad {
    enum Level {
        case light
        case steady
        case busy
        case full

        var color: Color {
            switch self {
            case .light: return .secondary
            case .steady: return .green
            case .busy: return .orange
            case .full: return .red
            }
        }

        var title: String {
            switch self {
            case .light: return L10n.pick("Light", "轻量")
            case .steady: return L10n.pick("Steady", "适中")
            case .busy: return L10n.pick("Busy", "偏满")
            case .full: return L10n.pick("Full", "过载")
            }
        }

        var fillOpacity: Double {
            switch self {
            case .light: return 0.12
            case .steady: return 0.16
            case .busy: return 0.18
            case .full: return 0.20
            }
        }
    }

    let timedMinutes: Int
    let taskCount: Int
    let highPriorityCount: Int

    var hasWork: Bool {
        timedMinutes > 0 || taskCount > 0 || highPriorityCount > 0
    }

    var level: Level {
        if timedMinutes >= 360 || taskCount >= 8 || highPriorityCount >= 3 {
            return .full
        }
        if timedMinutes >= 240 || taskCount >= 5 || highPriorityCount >= 2 {
            return .busy
        }
        if timedMinutes > 0 || taskCount > 0 {
            return .steady
        }
        return .light
    }

    var hoursLabel: String {
        guard timedMinutes > 0 else { return "0h" }
        let hours = timedMinutes / 60
        let minutes = timedMinutes % 60
        if minutes == 0 { return "\(hours)h" }
        if hours == 0 { return "\(minutes)m" }
        return "\(hours)h \(minutes)m"
    }

    var shortLabel: String {
        "\(hoursLabel) · \(taskCount)"
    }

    var detailLabel: String {
        L10n.pick(
            "\(level.title): \(hoursLabel) scheduled, \(taskCount) tasks, \(highPriorityCount) high priority",
            "\(level.title)：\(hoursLabel) 日程，\(taskCount) 个任务，\(highPriorityCount) 个高优先级"
        )
    }

    static func measure(_ items: [ProjectItem], calendar: Calendar = .current) -> PlanDayLoad {
        let activeItems = items.filter { !$0.isCompleted }
        let taskCount = activeItems.filter { $0.facetKind == .task }.count
        let highPriorityCount = activeItems.filter { item in
            item.facetKind == .task && (1...4).contains(item.priority)
        }.count
        let timedMinutes = activeItems.reduce(0) { total, item in
            guard item.facetKind == .event,
                  !item.isAllDay,
                  let start = item.date else { return total }
            let end = item.endDate ?? calendar.date(byAdding: .hour, value: 1, to: start) ?? start
            return total + max(15, Int(end.timeIntervalSince(start) / 60))
        }
        return PlanDayLoad(
            timedMinutes: timedMinutes,
            taskCount: taskCount,
            highPriorityCount: highPriorityCount
        )
    }
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
