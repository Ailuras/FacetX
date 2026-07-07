import FacetXCore
import SwiftUI

struct PlanSortMenu: View {
    @Binding var selection: PlanSortOption
    let onSelect: (PlanSortOption) -> Void

    var body: some View {
        Menu {
            ForEach(PlanSortOption.allCases) { option in
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

extension PlanSortOption {
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
