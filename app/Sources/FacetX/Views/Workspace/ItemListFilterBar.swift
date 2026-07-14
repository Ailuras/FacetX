import AppKit
import FacetXCore
import SwiftUI

/// The active include/exclude tag filters with quick removal. Shared by the
/// All and Plan views so the filter chips look identical everywhere.
struct ActiveTagFilterBar: View {
    @EnvironmentObject private var settings: AppSettings
    @Binding var tagFilter: TagFilter

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(tagFilter.included).sorted(), id: \.self) { tag in
                miniTagBadge(tag: tag, included: true)
            }
            ForEach(Array(tagFilter.excluded).sorted(), id: \.self) { tag in
                miniTagBadge(tag: tag, included: false)
            }
            Button {
                tagFilter.clear()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L10n.pick("Clear all tag filters", "清除所有标签筛选"))
        }
    }

    private func miniTagBadge(tag: String, included: Bool) -> some View {
        let color = settings.tagColor(for: tag)
        return Button {
            if included { tagFilter.included.remove(tag) }
            else { tagFilter.excluded.remove(tag) }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: included ? "plus" : "minus")
                    .font(.system(size: 8, weight: .bold))
                Text(tag)
                    .font(.system(size: 11, weight: .semibold))
                    .strikethrough(!included)
            }
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(included ? 0.14 : 0.06))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(color.opacity(included ? 0.30 : 0.55),
                            style: StrokeStyle(lineWidth: 1, dash: included ? [] : [2.5, 2]))
            )
        }
        .buttonStyle(.plain)
        .help(included ? L10n.pick("Remove include filter", "移除包含筛选")
                       : L10n.pick("Remove exclude filter", "移除排除筛选"))
    }
}

/// A single pill button matching the All view's action-cluster styling. Shared
/// so the Plan controls are pixel-identical to the All view.
struct FilterPillButton: View {
    let systemName: String
    let help: String
    var active: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            WorkspaceActionIcon(systemName: systemName, active: active)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct ItemFilterMenuButton: View {
    @Binding var itemFilter: ItemListFilter

    var body: some View {
        Menu {
            Section(L10n.pick("Kind", "类型")) {
                kindButton(.all)
                kindButton(.tasks)
                kindButton(.events)
            }
            Section(L10n.pick("Date", "日期")) {
                dateButton(.all)
                dateButton(.today)
                dateButton(.nextSevenDays)
            }
            if itemFilter.isActive {
                Divider()
                Button {
                    itemFilter = ItemListFilter()
                } label: {
                    Label(L10n.pick("Clear Filter", "清除筛选"), systemImage: "xmark.circle")
                }
            }
        } label: {
            WorkspaceActionIcon(
                systemName: itemFilter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle",
                active: itemFilter.isActive
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(itemFilter.isActive ? L10n.pick("Filter items", "筛选条目")
                                  : L10n.pick("Add an item filter", "添加条目筛选"))
    }

    private func kindName(_ scope: ItemKindScope) -> String {
        switch scope {
        case .all:    return L10n.pick("All", "全部")
        case .tasks:  return L10n.pick("Tasks", "任务")
        case .events: return L10n.pick("Events", "事件")
        }
    }

    private func dateName(_ scope: ItemDateScope) -> String {
        switch scope {
        case .all:            return L10n.pick("Any Time", "任意时间")
        case .today:          return L10n.pick("Today", "今天")
        case .nextSevenDays:  return L10n.pick("Next 7 Days", "未来 7 天")
        }
    }

    private func kindButton(_ scope: ItemKindScope) -> some View {
        Button {
            itemFilter.kindScope = scope
        } label: {
            HStack {
                Text(kindName(scope))
                if itemFilter.kindScope == scope {
                    Image(systemName: "checkmark")
                }
            }
        }
    }

    private func dateButton(_ scope: ItemDateScope) -> some View {
        Button {
            itemFilter.dateScope = scope
        } label: {
            HStack {
                Text(dateName(scope))
                if itemFilter.dateScope == scope {
                    Image(systemName: "checkmark")
                }
            }
        }
    }
}

/// Shared action cluster for All and Plan item lists.
struct ItemActionCluster<Accessory: View>: View {
    @Binding var itemFilter: ItemListFilter
    @Binding var showCompleted: Bool
    /// Optional overdue-visibility toggle. `nil` hides the pill (Plan, which
    /// don't surface overdue separately); the All view passes a real binding.
    var showOverdue: Binding<Bool>?
    var animation: Animation = FacetTheme.listSpring
    let onAdd: () -> Void
    /// When set, the "+" becomes a menu letting the user pick what to create.
    /// `nil` keeps the plain add button (used by Plan, which adds by date).
    var onCreateKind: ((ProjectItem.Kind) -> Void)?
    private let accessory: Accessory

    init(
        itemFilter: Binding<ItemListFilter>,
        showCompleted: Binding<Bool>,
        showOverdue: Binding<Bool>? = nil,
        animation: Animation = FacetTheme.listSpring,
        onAdd: @escaping () -> Void,
        onCreateKind: ((ProjectItem.Kind) -> Void)? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self._itemFilter = itemFilter
        self._showCompleted = showCompleted
        self.showOverdue = showOverdue
        self.animation = animation
        self.onAdd = onAdd
        self.onCreateKind = onCreateKind
        self.accessory = accessory()
    }

    var body: some View {
        WorkspaceActionGroup {
            accessory
            ItemFilterMenuButton(itemFilter: $itemFilter)
            if let showOverdue {
                FilterPillButton(
                    systemName: showOverdue.wrappedValue ? "clock.badge.exclamationmark.fill" : "clock.badge.exclamationmark",
                    help: showOverdue.wrappedValue ? L10n.pick("Hide overdue items", "隐藏已逾期")
                                                   : L10n.pick("Show overdue items", "显示已逾期"),
                    active: showOverdue.wrappedValue
                ) {
                    withAnimation(animation) { showOverdue.wrappedValue.toggle() }
                }
            }
            FilterPillButton(
                systemName: showCompleted ? "checkmark.circle.fill" : "checkmark.circle",
                help: showCompleted ? L10n.pick("Hide completed items", "隐藏已完成")
                                    : L10n.pick("Show completed items", "显示已完成"),
                active: showCompleted
            ) {
                withAnimation(animation) { showCompleted.toggle() }
            }
            if let onCreateKind {
                createMenu(onCreateKind)
            } else {
                FilterPillButton(systemName: "plus",
                                 help: L10n.pick("Add an item to this project", "向该项目添加条目"),
                                 action: onAdd)
            }
        }
    }

    private func createMenu(_ onCreateKind: @escaping (ProjectItem.Kind) -> Void) -> some View {
        Menu {
            Button { onCreateKind(.reminder) } label: { Label(ProjectItem.Kind.reminder.singularTitle, systemImage: ProjectItem.Kind.reminder.systemImage) }
            Button { onCreateKind(.event) } label: { Label(ProjectItem.Kind.event.singularTitle, systemImage: ProjectItem.Kind.event.systemImage) }
        } label: {
            WorkspaceActionIcon(systemName: "plus")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L10n.pick("Add an item to this project", "向该项目添加条目"))
    }
}

extension ItemActionCluster where Accessory == EmptyView {
    init(
        itemFilter: Binding<ItemListFilter>,
        showCompleted: Binding<Bool>,
        animation: Animation = FacetTheme.listSpring,
        onAdd: @escaping () -> Void
    ) {
        self.init(
            itemFilter: itemFilter,
            showCompleted: showCompleted,
            animation: animation,
            onAdd: onAdd,
            accessory: { EmptyView() }
        )
    }
}
