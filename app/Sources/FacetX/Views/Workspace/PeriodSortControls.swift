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
    WorkspaceActionIcon(systemName: systemImage, active: active)
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
