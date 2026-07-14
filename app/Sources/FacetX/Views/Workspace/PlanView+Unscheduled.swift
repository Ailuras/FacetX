import FacetXCore
import SwiftUI

extension PlanView {
    var unscheduledScopedItems: [WorkItem] {
        var result = allItems.filter { item in
            item.kind == .reminder
                && item.kind == .reminder
                && item.date == nil
                && !item.isCompleted
        }
        result = ItemQuery.filtered(result, by: tagFilter)
        result = ItemQuery.filtered(result, by: itemFilter)
        result = ItemQuery.searched(result, query: searchText)
        return pinnedFirst(result)
    }

    @ViewBuilder var unscheduledSection: some View {
        if !unscheduledScopedItems.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                unscheduledHeader

                if !unscheduledCollapsed {
                    VStack(spacing: 5) {
                        ForEach(unscheduledScopedItems) { item in
                            unscheduledRow(item)
                        }
                    }
                }
            }
            .padding(12)
            .background(FacetTheme.quietPanel)
            .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                    .stroke(WorkItem.Kind.reminder.color.opacity(0.18), lineWidth: 1)
            )
        }
    }

    private var unscheduledHeader: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(listAnimation) {
                    unscheduledCollapsed.toggle()
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(unscheduledCollapsed ? 0 : 90))
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .help(unscheduledCollapsed ? L10n.pick("Expand unscheduled tasks", "展开未安排任务")
                                       : L10n.pick("Collapse unscheduled tasks", "折叠未安排任务"))

            Label(L10n.pick("Unscheduled", "未安排"), systemImage: "tray")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.86))

            Text("\(unscheduledScopedItems.count)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(WorkItem.Kind.reminder.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(WorkItem.Kind.reminder.color.opacity(0.12))
                .clipShape(Capsule())

            Spacer(minLength: 0)
        }
        .frame(minHeight: 24)
    }

    private func unscheduledRow(_ item: WorkItem) -> some View {
        HStack(spacing: 8) {
            StandardItemRow(
                item: item,
                workPrefix: work.prefix,
                selectedItem: $selectedItem,
                inlineEdit: $inlineEdit,
                onDragStart: {
                    switchToManualSortFromCurrentOrder()
                    return ItemDragHelpers.startDrag(
                        item: item,
                        items: allItems,
                        draggedItem: &draggedItem,
                        dragSnapshot: &dragSnapshot,
                        cancelDrag: {
                            if draggedItem != nil { cancelUnscheduledDrag() }
                        }
                    )
                },
                onReload: {
                    await reload()
                },
                onDeleteRequest: { item in
                    itemToDelete = item
                }
            )
            .frame(maxWidth: .infinity)

            HStack(spacing: 2) {
                unscheduledQuickScheduleButton(
                    item: item,
                    title: L10n.pick("Today", "今天"),
                    systemImage: "calendar",
                    date: todayStart
                )
                unscheduledQuickScheduleButton(
                    item: item,
                    title: L10n.pick("Tomorrow", "明天"),
                    systemImage: "sunrise",
                    date: tomorrowStart
                )
                unscheduledQuickScheduleButton(
                    item: item,
                    title: L10n.pick("Friday", "周五"),
                    systemImage: "calendar.badge.clock",
                    date: weekFriday
                )
                unscheduledQuickScheduleButton(
                    item: item,
                    title: L10n.pick("Next Week", "下周"),
                    systemImage: "arrow.right.to.line",
                    date: week.shifted(by: 1).startDate
                )
            }
            .fixedSize()
        }
        .opacity(draggedItem?.id == item.id ? 0.32 : 1.0)
    }

    private func unscheduledQuickScheduleButton(item: WorkItem, title: String, systemImage: String, date: Date) -> some View {
        Button {
            scheduleUnscheduledItem(item, to: date)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 26, height: FacetTheme.chipHeight)
                .contentShape(Rectangle())
                .facetHoverSurface(tint: .secondary,
                                   fill: Color.primary.opacity(0.04),
                                   hoverFill: WorkItem.Kind.reminder.color.opacity(0.12),
                                   hoverStroke: WorkItem.Kind.reminder.color.opacity(0.30))
        }
        .buttonStyle(.plain)
        .help(L10n.pick("Schedule to \(title)", "安排到\(title)"))
    }

    private func scheduleUnscheduledItem(_ item: WorkItem, to date: Date) {
        withAnimation(listAnimation) {
            if let index = allItems.firstIndex(where: { $0.id == item.id }) {
                allItems[index] = item.replacingDate(date)
            }
        }
        Task {
            await ItemActionHelpers.reschedule(item, toDay: date, ek: ek)
            await reload()
        }
    }

    private func cancelUnscheduledDrag() {
        if let snapshot = dragSnapshot {
            withAnimation(listAnimation) { allItems = snapshot }
        }
        dragSnapshot = nil
        draggedItem = nil
        dropTargetDate = nil
    }

    private func pinnedFirst(_ items: [WorkItem]) -> [WorkItem] {
        items.filter(\.isPinned) + items.filter { !$0.isPinned }
    }

    private var todayStart: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var tomorrowStart: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
    }

    private var weekFriday: Date {
        Calendar(identifier: .iso8601).date(byAdding: .day, value: 4, to: week.startDate) ?? week.startDate
    }
}
