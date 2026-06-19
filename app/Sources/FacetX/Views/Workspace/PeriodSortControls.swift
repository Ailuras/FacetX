import FacetXCore
import SwiftUI

struct WeekSortMenu: View {
    @Binding var selection: WeekSortOption
    let onSelect: (WeekSortOption) -> Void

    var body: some View {
        Menu {
            ForEach(WeekSortOption.allCases) { option in
                Button {
                    onSelect(option)
                } label: {
                    Label(option.displayName, systemImage: option.systemImage)
                }
            }
        } label: {
            sortLabel(systemImage: selection.systemImage, active: selection != .manual)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L10n.pick("Sort: \(selection.displayName)", "排序：\(selection.displayName)"))
    }
}

struct MonthSortMenu: View {
    @Binding var selection: MonthSortOption
    let onSelect: (MonthSortOption) -> Void

    var body: some View {
        Menu {
            ForEach(MonthSortOption.allCases) { option in
                Button {
                    onSelect(option)
                } label: {
                    Label(option.displayName, systemImage: option.systemImage)
                }
            }
        } label: {
            sortLabel(systemImage: selection.systemImage, active: selection != .manual)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L10n.pick("Sort: \(selection.displayName)", "排序：\(selection.displayName)"))
    }
}

private func sortLabel(systemImage: String, active: Bool) -> some View {
    Image(systemName: systemImage)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(active ? Color.accentColor : .secondary)
        .frame(width: 26, height: 24)
        .background(active ? Color.accentColor.opacity(0.14) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
}

extension WeekSortOption {
    var displayName: String {
        switch self {
        case .manual: return L10n.pick("Manual", "手动")
        case .scheduleAsc: return L10n.pick("Schedule", "日程时间")
        case .priorityDesc: return L10n.pick("Priority", "优先级")
        case .kindAsc: return L10n.pick("Type", "类型")
        }
    }

    var systemImage: String {
        switch self {
        case .manual: return "list.number"
        case .scheduleAsc: return "clock"
        case .priorityDesc: return "flag.fill"
        case .kindAsc: return "square.grid.2x2"
        }
    }
}

extension MonthSortOption {
    var displayName: String {
        switch self {
        case .manual: return L10n.pick("Manual", "手动")
        case .dateAsc: return L10n.pick("Date", "日期")
        case .priorityDesc: return L10n.pick("Priority", "优先级")
        case .kindAsc: return L10n.pick("Type", "类型")
        case .titleAsc: return L10n.pick("Title", "标题")
        }
    }

    var systemImage: String {
        switch self {
        case .manual: return "list.number"
        case .dateAsc: return "calendar"
        case .priorityDesc: return "flag.fill"
        case .kindAsc: return "square.grid.2x2"
        case .titleAsc: return "textformat.abc"
        }
    }
}
