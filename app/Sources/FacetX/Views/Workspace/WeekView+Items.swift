import FacetXCore
import SwiftUI
import UniformTypeIdentifiers

extension WeekView {
    @ViewBuilder var itemsSection: some View {
        if loading {
            ProgressView()
        } else if nonGoalItems.isEmpty && hasActiveSearch {
            Text("No items match this search.")
                .font(.callout).foregroundStyle(.secondary)
        } else {
            List {
                ForEach(dayGroups) { group in
                    daySection(group: group)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .animation(listAnimation, value: nonGoalItems.map { "\($0.id)-\($0.isCompleted)" })
        }
    }

    private func daySection(group: DayGroup) -> some View {
        let cal = Calendar.current
        let isDropTarget = dropTargetDate.map { cal.isDate($0, inSameDayAs: group.date) } ?? false

        return VStack(alignment: .leading, spacing: 0) {
            // ── Header ──
            HStack(spacing: 6) {
                Text(group.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(group.isToday ? Color.accentColor : .secondary)
                if group.isToday {
                    Text("Today")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                }
                Spacer()
                Text("\(group.items.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                Button {
                    createDate = DateWrapper(date: group.date)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Add item for \(group.label)")
            }
            .padding(.vertical, 4)

            // ── Content ──
            if group.items.isEmpty {
                Text("No items")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 6) {
                    ForEach(group.items) { item in
                        weekItemRow(item)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isDropTarget ? Color.accentColor.opacity(0.08) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isDropTarget ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1.5)
        )
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14))
        .onDrop(of: [.text], delegate: WeekDayDropDelegate(
            date: group.date,
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
        ))
    }

    func weekItemRow(_ item: ProjectItem) -> some View {
        StandardItemRow(
            item: item,
            projectPrefix: project.prefix,
            selectedItem: $selectedItem,
            inlineEdit: $inlineEdit,
            onDragStart: {
                ItemDragHelpers.startDrag(
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
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .top)),
            removal: .opacity.combined(with: .scale(scale: 0.98))
        ))
        .onDrop(of: [.text], delegate: WeekItemDropDelegate(
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
        withAnimation(FacetTheme.dragPreviewAnimation) {
            allItems.remove(at: fromIndex)

            if let target, target.id != source.id,
               let targetIndex = allItems.firstIndex(where: { $0.id == target.id }) {
                allItems.insert(movedItem, at: targetIndex)
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
                notes: current.notes,
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
        let cal = Calendar.current
        guard let oldDate = item.date else { return day }
        if (item.kind == .event && !item.isAllDay) || item.hasTime {
            let hour = cal.component(.hour, from: oldDate)
            let minute = cal.component(.minute, from: oldDate)
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        return day
    }

    private func movedEndDate(original item: ProjectItem, currentStart: Date) -> Date? {
        guard item.kind == .event else { return nil }
        let cal = Calendar.current
        if item.isAllDay {
            return cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: currentStart))
        }
        guard let oldStart = item.date, let oldEnd = item.endDate else { return nil }
        let duration = oldEnd.timeIntervalSince(oldStart)
        return currentStart.addingTimeInterval(duration > 0 ? duration : 3600)
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

struct WeekItemDropDelegate: DropDelegate {
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

struct WeekDayDropDelegate: DropDelegate {
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
