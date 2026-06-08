import FacetXCore
import SwiftUI
import UniformTypeIdentifiers

/// Single-project month view: a calendar grid showing items whose due/start date
/// falls within the selected month. Tap a day to see its items in the list below.
struct MonthView: View {
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: ProjectStore

    let project: Project
    let searchText: String
    @Binding var showCompleted: Bool
    @Binding var selectedItem: ProjectItem?
    @Binding var tagFilter: TagFilter
    @Binding var itemFilter: ItemListFilter
    let refreshTrigger: Int
    let onCreateItem: (Date?) -> Void

    @State private var month = MonthYear.containing(Date())
    @State private var allItems: [ProjectItem] = []
    @State private var selectedDay: Int? = nil
    @State private var inlineEdit = ItemInlineEditState()
    @State private var itemToDelete: ProjectItem? = nil
    @State private var draggedItem: ProjectItem? = nil
    @State private var dragSnapshot: [ProjectItem]? = nil

    private var listAnimation: Animation { FacetTheme.listSpring }

    /// Month items after tag + search filtering but *before* the completed-items
    /// visibility filter. Preserves `allItems`' manual order (shared with the
    /// Week and All views) rather than re-sorting by date, so drag-reordering in
    /// the day detail list is meaningful.
    private var monthScopedItems: [ProjectItem] {
        var result = allItems.filter { item in
            guard let d = item.date else { return false }
            return month.contains(d)
        }
        result = ItemQuery.filtered(result, by: tagFilter)
        result = ItemQuery.filtered(result, by: itemFilter)
        return ItemQuery.searched(result, query: searchText)
    }

    private var monthItems: [ProjectItem] {
        ItemQuery.completedVisibility(monthScopedItems, showCompleted: showCompleted)
    }

    private var hiddenReminderCount: Int {
        guard !showCompleted else { return 0 }
        return monthScopedItems.filter { $0.kind == .reminder && $0.isCompleted }.count
    }

    private var itemsByDay: [Int: [ProjectItem]] {
        Dictionary(grouping: monthItems) { item in
            guard let d = item.date else { return 0 }
            return MonthYear.calendar.component(.day, from: d)
        }
    }

    private var selectedDayItems: [ProjectItem] {
        guard let day = selectedDay else { return [] }
        return itemsByDay[day] ?? []
    }

    private var gridHeight: CGFloat {
        let offset = month.firstWeekdayOffset
        let days = month.numberOfDays
        let rows = (offset + days + 6) / 7
        return CGFloat(rows) * 80
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            monthNav
            weekdayHeader
            calendarGrid
                .frame(height: gridHeight)

            if let day = selectedDay {
                Divider()
                    .padding(.top, 8)
                dayDetailView(for: day)
            } else {
                Spacer()
                Text("Tap a day to view its items")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 24)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(FacetTheme.canvas)
        .task(id: reloadKey) { await reload() }
        .onChange(of: ek.changeToken) { Task { await reload() } }
        .onChange(of: settings.changeToken) { Task { await reload() } }
        .onChange(of: refreshTrigger) { Task { await reload() } }
        .onChange(of: month) { _, _ in selectedDay = nil }
        .alert("Delete item?", isPresented: .init(
            get: { itemToDelete != nil },
            set: { if !$0 { itemToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { itemToDelete = nil }
            Button("Delete", role: .destructive) {
                if let item = itemToDelete {
                    Task { await ItemActionHelpers.deleteItem(item, ek: ek); await reload() }
                }
                itemToDelete = nil
            }
        } message: {
            Text(itemToDelete?.content ?? "")
        }
    }

    private var hasActiveSearch: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var reloadKey: String {
        "\(project.id.uuidString)-\(month.id)"
    }

    // ── Month navigation ─────────────────────────────────────────────────────
    private var monthNav: some View {
        PeriodNavigationBar(
            title: month.label,
            subtitle: "Month \(month.id)",
            previousHelp: "Previous month",
            nextHelp: "Next month",
            currentHelp: "Go to current month",
            onPrevious: { month = month.shifted(by: -1) },
            onNext: { month = month.shifted(by: 1) },
            onCurrent: { month = MonthYear.containing(Date()) }
        ) {
            if hasActiveSearch {
                FacetInfoBadge(
                    text: "\(monthItems.count) results",
                    systemImage: "magnifyingglass",
                    tint: .secondary,
                    fill: Color.accentColor.opacity(0.08)
                )
            }
            if !showCompleted && hiddenReminderCount > 0 {
                FacetInfoBadge(
                    text: "\(hiddenReminderCount) hidden",
                    systemImage: "eye.slash",
                    tint: .secondary,
                    fill: Color.orange.opacity(0.08)
                )
            }
            if !tagFilter.isEmpty {
                ActiveTagFilterBar(tagFilter: $tagFilter)
            }
            if itemFilter.isActive {
                FacetInfoBadge(
                    text: "\(monthItems.count) shown",
                    systemImage: "line.3.horizontal.decrease.circle",
                    tint: .secondary,
                    fill: Color.accentColor.opacity(0.08)
                )
            }
            ItemActionCluster(itemFilter: $itemFilter, showCompleted: $showCompleted, animation: listAnimation) {
                if let selectedDay, let date = month.dateForDay(selectedDay) {
                    onCreateItem(date)
                } else {
                    onCreateItem(month.startDate)
                }
            }
        }
    }

    // ── Weekday header ───────────────────────────────────────────────────────
    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { day in
                Text(day)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
        }
        .background(FacetTheme.canvas)
    }

    // ── Calendar grid ────────────────────────────────────────────────────────
    private var calendarGrid: some View {
        let offset = month.firstWeekdayOffset
        let days = month.numberOfDays
        let totalCells = ((offset + days + 6) / 7) * 7

        return ScrollView {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
                spacing: 0
            ) {
                ForEach(0..<totalCells, id: \.self) { index in
                    let dayNumber = index - offset + 1
                    if dayNumber > 0 && dayNumber <= days {
                        dayCell(day: dayNumber)
                    } else {
                        emptyCell
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func dayCell(day: Int) -> some View {
        let items = itemsByDay[day] ?? []
        let scheduleItems = items.filter { $0.kind == .event }
        let taskItems = items.filter { $0.kind == .reminder }
        let shownSchedule = Array(scheduleItems.prefix(2))
        let shownTasks = Array(taskItems.prefix(max(0, 3 - shownSchedule.count)))
        let hiddenCount = items.count - shownSchedule.count - shownTasks.count
        let isToday = month.isToday(day: day)
        let hasItems = !items.isEmpty

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if hasItems {
                    monthCountPills(scheduleCount: scheduleItems.count, taskCount: taskItems.count,
                                    emphasized: isToday)
                }

            Spacer()

            Text("\(day)")
                .font(.system(size: 12, weight: isToday ? .bold : .regular))
                .foregroundStyle(isToday ? Color.accentColor : .primary)
                .padding(.horizontal, isToday ? 6 : 0)
                .padding(.vertical, isToday ? 2 : 0)
                .background(isToday ? Color.accentColor.opacity(0.12) : Color.clear)
                .clipShape(Capsule())
            }
            .padding(.top, 5)
            .padding(.horizontal, 6)

            VStack(alignment: .leading, spacing: 1) {
                ForEach(shownSchedule) { item in
                    dayItemRow(item: item)
                }
                ForEach(shownTasks) { item in
                    dayItemRow(item: item)
                }
                if hiddenCount > 0 {
                    Text("+\(hiddenCount)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.10))
                        .clipShape(Capsule())
                        .padding(.leading, 2)
                        .help("\(hiddenCount) more items on this day")
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)

            Spacer(minLength: 0)
        }
        .frame(minHeight: 80)
        .background(dayBackground(isToday: isToday, hasItems: hasItems))
        .overlay(
            Rectangle()
                .stroke(
                    isToday ? Color.accentColor.opacity(0.45) : (hasItems ? Color.accentColor.opacity(0.14) : FacetTheme.hairline),
                    lineWidth: isToday ? 1.5 : 0.5
                )
        )
        .contentShape(Rectangle())
        .highPriorityGesture(
            TapGesture(count: 1)
                .onEnded {
                    withAnimation(.easeOut(duration: 0.15)) {
                        if selectedDay == day {
                            selectedDay = nil
                        } else {
                            selectedDay = day
                        }
                    }
                }
        )
        .onTapGesture(count: 2) {
            if let date = month.dateForDay(day) {
                onCreateItem(date)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(selectedDay == day ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }

    private func monthCountPills(scheduleCount: Int, taskCount: Int, emphasized: Bool) -> some View {
        HStack(spacing: 3) {
            if scheduleCount > 0 {
                monthCountPill(value: scheduleCount, systemImage: "calendar", color: .blue, emphasized: emphasized)
            }
            if taskCount > 0 {
                monthCountPill(value: taskCount, systemImage: "checklist", color: .green, emphasized: emphasized)
            }
        }
    }

    private func monthCountPill(value: Int, systemImage: String, color: Color, emphasized: Bool) -> some View {
        HStack(spacing: 2) {
            Image(systemName: systemImage)
                .font(.system(size: 7, weight: .bold))
            Text("\(value)")
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(emphasized ? Color.accentColor : color)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background((emphasized ? Color.accentColor : color).opacity(0.10))
        .clipShape(Capsule())
    }

    private var emptyCell: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(minHeight: 80)
            .overlay(Rectangle().stroke(FacetTheme.hairline, lineWidth: 0.5))
    }

    // ── Selected day detail ───────────────────────────────────────────────────
    @ViewBuilder
    private func dayDetailView(for day: Int) -> some View {
        let items = selectedDayItems
        let dayDate = month.dateForDay(day)

        VStack(spacing: 0) {
            dayDetailHeader(day: day, date: dayDate)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            Divider()

            if items.isEmpty {
                VStack(spacing: 4) {
                    Spacer()
                    Image(systemName: "calendar.day.timeline.left")
                        .font(.system(size: 18))
                        .foregroundStyle(.tertiary)
                    Text("No items for this day")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(items) { item in
                        dayDetailItemRow(item)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 3, leading: 14, bottom: 3, trailing: 14))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func dayDetailItemRow(_ item: ProjectItem) -> some View {
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
            onReload: { await reload() },
            onDeleteRequest: { item in
                itemToDelete = item
            }
        )
        .onDrop(of: [.text], delegate: ItemDropDelegate(
            item: item,
            draggedItem: $draggedItem,
            onEntered: { dragged, target in moveItem(from: dragged, to: target) },
            onDrop: { finishDrag() }
        ))
        .opacity(draggedItem?.id == item.id ? 0.32 : 1.0)
    }

    // ── Drag reorder (shares the project's manual order with Week / All) ───────
    private func moveItem(from source: ProjectItem, to destination: ProjectItem) {
        guard let fromIndex = allItems.firstIndex(where: { $0.id == source.id }),
              let toIndex = allItems.firstIndex(where: { $0.id == destination.id }),
              fromIndex != toIndex else { return }
        withAnimation(FacetTheme.dragPreviewAnimation) {
            let moved = allItems.remove(at: fromIndex)
            allItems.insert(moved, at: toIndex)
        }
    }

    private func finishDrag() {
        guard draggedItem != nil else { return }
        store.setItemOrder(projectID: project.id, orderedIDs: allItems.map(\.id))
        dragSnapshot = nil
        draggedItem = nil
    }

    private func cancelDrag() {
        if let snapshot = dragSnapshot {
            withAnimation(listAnimation) { allItems = snapshot }
        }
        dragSnapshot = nil
        draggedItem = nil
    }

    private func dayDetailHeader(day: Int, date: Date?) -> some View {
        HStack {
            Text(dayHeaderLabel(for: date, day: day))
                .font(.headline)
            Spacer()
            Button {
                if let date = date {
                    onCreateItem(date)
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 20)
                    .background(Color.accentColor.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .help("Add item for this day")
        }
    }

    private func dayHeaderLabel(for date: Date?, day: Int) -> String {
        guard let date = date else { return "Day \(day)" }
        let df = DateFormatter()
        df.dateFormat = "EEEE, MMMM d"
        return df.string(from: date)
    }

    private func dayItemRow(item: ProjectItem) -> some View {
        let color = item.kind == .event ? Color.blue : FacetTheme.priorityColor(item.priority)
        return HStack(spacing: 3) {
            Image(systemName: item.kind == .event ? "calendar" : (item.isCompleted ? "checkmark.circle.fill" : "circle"))
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 10)
            Text(item.content)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(item.isCompleted ? .secondary : .primary)
                .strikethrough(item.isCompleted)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(item.kind == .event ? 0.10 : 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .contentShape(Rectangle())
        .itemSelectionGestures(
            item: item,
            selectedItem: $selectedItem
        )
        .help(item.content)
    }

    private func dayBackground(isToday: Bool, hasItems: Bool) -> Color {
        if isToday { return FacetTheme.softAccent }
        if hasItems { return Color.accentColor.opacity(0.035) }
        return Color.clear
    }

    private func reload() async {
        let requestedMonth = month
        let fetched = await ek.items(forProject: project.prefix,
                                      enabledReminderLists: settings.effectiveReminderListNames,
                                      enabledCalendars: settings.effectiveCalendarNames,
                                      eventStartDate: requestedMonth.startDate,
                                      eventEndDate: requestedMonth.endDate)
        guard !Task.isCancelled, requestedMonth == month else { return }
        let sortedItems = ItemArrangement.arranged(fetched, savedOrder: project.itemOrder)
        store.reportTags(projectID: project.id, items: sortedItems)
        if allItems.isEmpty {
            allItems = sortedItems
        } else {
            withAnimation(listAnimation) {
                allItems = sortedItems
            }
        }
    }
}
