import FacetXCore
import SwiftUI
import UniformTypeIdentifiers

extension PlanView {
    @ViewBuilder var itemsSection: some View {
        if loading {
            ProgressView()
        } else if nonGoalItems.isEmpty && hasActiveSearch {
            Text(L10n.t(.noItemsSearch))
                .font(.callout).foregroundStyle(.secondary)
        } else {
            List {
                ForEach(dayGroups) { group in
                    daySection(group: group)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .thinScrollIndicators()
        }
    }

    /// Emits a day's header followed by each item as its own List row. Keeping
    /// the items as direct rows (rather than nesting them in a VStack) lets the
    /// per-row `.swipeActions` work. The day-level drop target now lives on the
    /// header and the empty placeholder row.
    @ViewBuilder
    func daySection(group: DayGroup) -> some View {
        dayHeader(group)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 10, leading: 14, bottom: 2, trailing: 14))

        if group.items.isEmpty {
            emptyDayRow(group)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 2, leading: 14, bottom: 6, trailing: 14))
        } else {
            ForEach(group.items) { item in
                planItemRow(item)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 3, leading: 14, bottom: 3, trailing: 14))
            }
        }
    }

    private func dayHeader(_ group: DayGroup) -> some View {
        let cal = Calendar.current
        let isDropTarget = dropTargetDate.map { cal.isDate($0, inSameDayAs: group.date) } ?? false
        let load = PlanDayLoad.measure(group.items)

        return HStack(spacing: 6) {
            Text(group.label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(group.isToday ? Color.accentColor : .secondary)
            if group.isToday {
                Text(L10n.t(.today))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
            }
            Spacer()
            dayLoadPill(load)
            Text("\(group.items.count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
            Button {
                onCreateItem(group.date)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(L10n.language == "zh" ? "为 \(group.label) 添加条目" : "Add item for \(group.label)")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(dayDropHighlight(isDropTarget, fill: 0.10))
        .onDrop(of: ItemDragHelpers.acceptedTypes, delegate: dayDropDelegate(for: group.date, calendar: cal))
    }

    @ViewBuilder
    private func dayLoadPill(_ load: PlanDayLoad) -> some View {
        if load.hasWork {
            HStack(spacing: 4) {
                Circle()
                    .fill(load.level.color.opacity(0.86))
                    .frame(width: 5, height: 5)
                Text(load.shortLabel)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(load.level.color)
            }
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(load.level.color.opacity(load.level.fillOpacity))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .help(load.detailLabel)
        }
    }

    private func emptyDayRow(_ group: DayGroup) -> some View {
        let cal = Calendar.current
        let isDropTarget = dropTargetDate.map { cal.isDate($0, inSameDayAs: group.date) } ?? false

        return Text(L10n.t(.noItems))
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(dayDropHighlight(isDropTarget, fill: 0.06))
            .onDrop(of: ItemDragHelpers.acceptedTypes, delegate: dayDropDelegate(for: group.date, calendar: cal))
    }

    private func dayDropHighlight(_ active: Bool, fill: Double) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(active ? Color.accentColor.opacity(fill) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(active ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1.5)
            )
    }

    func dayDropDelegate(for date: Date, calendar cal: Calendar) -> PlanDayDropDelegate {
        PlanDayDropDelegate(
            date: date,
            draggedItem: $draggedItem,
            onEntered: { date in
                withAnimation(.easeOut(duration: 0.12)) {
                    dropTargetDate = date
                }
                if let draggedItem {
                    previewMove(item: draggedItem, toDay: date, before: nil)
                }
            },
            onExited: { date in
                withAnimation(.easeOut(duration: 0.12)) {
                    if dropTargetDate.map({ cal.isDate($0, inSameDayAs: date) }) == true {
                        dropTargetDate = nil
                    }
                }
            },
            onDrop: {
                finishDrag()
            }
        )
    }

    func planItemRow(_ item: ProjectItem) -> some View {
        StandardItemRow(
            item: item,
            projectPrefix: project.prefix,
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
                        if draggedItem != nil { cancelDrag() }
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
        .onDrop(of: ItemDragHelpers.acceptedTypes, delegate: PlanItemDropDelegate(
            item: item,
            draggedItem: $draggedItem,
            onEntered: { dragged, target in
                guard let targetDate = target.date else { return }
                previewMove(item: dragged, toDay: targetDate, before: target)
            },
            onDrop: {
                finishDrag()
            }
        ))
    }

    private func previewMove(item source: ProjectItem, toDay destinationDay: Date, before target: ProjectItem?) {
        guard let fromIndex = allItems.firstIndex(where: { $0.id == source.id }) else {
            return
        }

        let movedItem = previewItem(source, movedToDay: destinationDay)
        // Capture the target's index *before* removing the source. Inserting at
        // this pre-removal index lands the item after the target when dragging
        // down and before it when dragging up — matching the All view's reorder
        // (computing it post-removal always inserted before, so dragging down
        // only swapped once you passed below the target).
        let targetIndex: Int? = target.flatMap { t in
            t.id == source.id ? nil : allItems.firstIndex(where: { $0.id == t.id })
        }
        withAnimation(FacetTheme.dragPreviewAnimation) {
            allItems.remove(at: fromIndex)

            if let targetIndex {
                allItems.insert(movedItem, at: min(targetIndex, allItems.count))
            } else {
                let insertionIndex = endIndexForDay(destinationDay)
                allItems.insert(movedItem, at: insertionIndex)
            }
            if selectedItem?.id == movedItem.id {
                selectedItem = movedItem
            }
        }
    }

    private func commitItemOrder() {
        sortOption = .manual
        store.setItemOrder(projectID: project.id, orderedIDs: allItems.map(\.id))
    }

    private func finishDrag() {
        guard let draggedItem else { return }
        let snapshot = dragSnapshot
        let originalItem = snapshot?.first(where: { $0.id == draggedItem.id }) ?? draggedItem
        guard let currentItem = allItems.first(where: { $0.id == draggedItem.id }) else {
            cancelDrag()
            return
        }

        let originalDate = originalItem.date
        let currentDate = currentItem.date
        let dateChanged = !sameDate(originalDate, currentDate)

        if dateChanged {
            self.draggedItem = nil
            dropTargetDate = nil
            persistMovedItem(original: originalItem, current: currentItem, snapshot: snapshot)
        } else {
            commitItemOrder()
            dragSnapshot = nil
            self.draggedItem = nil
            dropTargetDate = nil
        }
    }

    private func persistMovedItem(original: ProjectItem, current: ProjectItem, snapshot: [ProjectItem]?) {
        guard let newDate = current.date else {
            cancelDrag()
            return
        }

        Task {
            let success = await ek.updateItem(
                id: current.id,
                project: current.projectPrefix,
                content: current.content,
                date: newDate,
                useDate: true,
                dateIncludesTime: current.hasTime,
                containerName: current.containerName,
                tags: current.tags,
                priority: current.priority,
                url: current.url,
                updateURL: false,
                isAllDay: nil,
                endDate: movedEndDate(original: original, currentStart: newDate)
            )

            if success {
                commitItemOrder()
                dragSnapshot = nil
            } else {
                if let snapshot {
                    withAnimation(listAnimation) {
                        allItems = snapshot
                    }
                }
                dragSnapshot = nil
            }
        }
    }

    private func previewItem(_ item: ProjectItem, movedToDay day: Date) -> ProjectItem {
        let newDate = movedStartDate(for: item, toDay: day)
        return item.replacingDate(newDate, endDate: movedEndDate(original: item, currentStart: newDate))
    }

    private func movedStartDate(for item: ProjectItem, toDay day: Date) -> Date {
        ItemActionHelpers.startDate(for: item, toDay: day)
    }

    private func movedEndDate(original item: ProjectItem, currentStart: Date) -> Date? {
        ItemActionHelpers.endDate(for: item, newStart: currentStart)
    }

    private func endIndexForDay(_ day: Date) -> Int {
        let cal = Calendar.current
        if let lastIndex = allItems.lastIndex(where: { item in
            guard let date = item.date else { return false }
            return cal.isDate(date, inSameDayAs: day)
        }) {
            return allItems.index(after: lastIndex)
        }
        return allItems.count
    }

    private func sameDate(_ a: Date?, _ b: Date?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return Calendar.current.compare(a, to: b, toGranularity: .minute) == .orderedSame
    }

    private func cancelDrag() {
        if let snapshot = dragSnapshot {
            withAnimation(listAnimation) { allItems = snapshot }
        }
        dragSnapshot = nil
        draggedItem = nil
        dropTargetDate = nil
    }

}

// MARK: – Drop delegate for dragging items onto a day block

struct PlanItemDropDelegate: DropDelegate {
    let item: ProjectItem
    @Binding var draggedItem: ProjectItem?
    var onEntered: (ProjectItem, ProjectItem) -> Void
    var onDrop: () -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedItem, draggedItem.id != item.id else { return }
        onEntered(draggedItem, item)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard draggedItem != nil else { return false }
        onDrop()
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
}

struct PlanDayDropDelegate: DropDelegate {
    let date: Date
    @Binding var draggedItem: ProjectItem?
    var onEntered: (Date) -> Void
    var onExited: (Date) -> Void
    var onDrop: () -> Void

    func dropEntered(info: DropInfo) {
        onEntered(date)
    }

    func dropExited(info: DropInfo) {
        onExited(date)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard draggedItem != nil else { return false }
        onDrop()
        onExited(date)
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
}
