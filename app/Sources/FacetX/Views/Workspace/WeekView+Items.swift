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
            },
            onExited: { date in
                withAnimation(.easeOut(duration: 0.12)) {
                    if dropTargetDate.map({ cal.isDate($0, inSameDayAs: date) }) == true {
                        dropTargetDate = nil
                    }
                }
            },
            onDrop: { item, date in
                moveItemToDay(item: item, date: date)
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
                dragSnapshot = allItems
                draggedItem = item
                return NSItemProvider(object: item.id as NSString)
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
        .onDrop(of: [.text], delegate: SameDayItemDropDelegate(
            item: item,
            draggedItem: $draggedItem,
            onDrop: {
                guard let dragged = draggedItem else { return false }
                guard sameDay(dragged, item) else { return false }
                moveItem(from: dragged, to: item)
                commitItemOrder()
                return true
            }
        ))
    }

    private func sameDay(_ a: ProjectItem, _ b: ProjectItem) -> Bool {
        guard let da = a.date, let db = b.date else { return false }
        return Calendar.current.isDate(da, inSameDayAs: db)
    }

    private func moveItem(from source: ProjectItem, to destination: ProjectItem) {
        guard let fromIndex = allItems.firstIndex(where: { $0.id == source.id }),
              let toIndex = allItems.firstIndex(where: { $0.id == destination.id }) else {
            return
        }
        if fromIndex != toIndex {
            withAnimation(.default) {
                let movedItem = allItems.remove(at: fromIndex)
                allItems.insert(movedItem, at: toIndex)
            }
        }
    }

    private func commitItemOrder() {
        store.setItemOrder(projectID: project.id, orderedIDs: allItems.map(\.id))
    }

    func moveItemToDay(item: ProjectItem, date: Date) {
        let cal = Calendar.current
        guard let oldDate = item.date else { return }
        guard !cal.isDate(oldDate, inSameDayAs: date) else { return }

        Task {
            let newDate: Date
            if item.kind == .event, !item.isAllDay {
                let hour = cal.component(.hour, from: oldDate)
                let minute = cal.component(.minute, from: oldDate)
                newDate = cal.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
            } else {
                newDate = date
            }

            let success = await ek.updateItem(
                id: item.id,
                project: item.projectPrefix,
                content: item.content,
                date: newDate,
                useDate: true,
                containerName: item.containerName,
                notes: item.notes,
                tags: item.tags,
                priority: item.priority,
                url: item.url,
                updateURL: false,
                isAllDay: nil,
                endDate: nil
            )
            if success {
                await reload()
            }
        }
    }

}

// MARK: – Drop delegate for dragging items onto a day block

struct SameDayItemDropDelegate: DropDelegate {
    let item: ProjectItem
    @Binding var draggedItem: ProjectItem?
    var onDrop: () -> Bool

    func performDrop(info: DropInfo) -> Bool {
        let handled = onDrop()
        if handled {
            self.draggedItem = nil
        }
        return handled
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
    var onDrop: (ProjectItem, Date) -> Void

    func dropEntered(info: DropInfo) {
        onEntered(date)
    }

    func dropExited(info: DropInfo) {
        onExited(date)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let draggedItem = draggedItem else { return false }
        onDrop(draggedItem, date)
        onExited(date)
        self.draggedItem = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
}
