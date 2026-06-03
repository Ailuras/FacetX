import FacetXCore
import SwiftUI

/// Single-project month view: a calendar grid showing items whose due/start date
/// falls within the selected month. Double-click a day cell to create a new item
/// for that date.
struct MonthView: View {
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var settings: AppSettings

    let project: Project
    let searchText: String
    let showCompleted: Bool
    @Binding var selectedItem: ProjectItem?
    let refreshTrigger: Int

    @State private var month = MonthYear.containing(Date())
    @State private var allItems: [ProjectItem] = []
    @State private var createDate: DateWrapper? = nil

    private var listAnimation: Animation { FacetTheme.listSpring }

    private var monthItems: [ProjectItem] {
        var items = ItemArrangement.inMonth(allItems, month)
        if !showCompleted {
            items = items.filter { !$0.isCompleted }
        }
        return items.filter { $0.matches(searchQuery: searchText) }
    }

    private var itemsByDay: [Int: [ProjectItem]] {
        Dictionary(grouping: monthItems) { item in
            guard let d = item.date else { return 0 }
            return MonthYear.calendar.component(.day, from: d)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            monthNav
            weekdayHeader
            calendarGrid
        }
        .background(FacetTheme.canvas)
        .task(id: reloadKey) { await reload() }
        .onChange(of: ek.changeToken) { Task { await reload() } }
        .onChange(of: settings.changeToken) { Task { await reload() } }
        .onChange(of: refreshTrigger) { Task { await reload() } }
        .sheet(item: $createDate) { wrapper in
            CreateItemView(project: project, initialDate: wrapper.date) {
                createDate = nil
                Task { await reload() }
            }
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
        HStack {
            Button { month = month.shifted(by: -1) } label: { Image(systemName: "chevron.left") }
                .help("Previous month")
            Spacer()
            VStack(spacing: 2) {
                Text(month.label).font(.headline)
                Text("Month \(month.id)").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button { month = month.shifted(by: 1) } label: { Image(systemName: "chevron.right") }
                .help("Next month")
            Button("Current month") { month = MonthYear.containing(Date()) }
                .font(.caption)
                .help("Go to current month")

            if hasActiveSearch {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("\(monthItems.count) results")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(0.08))
                )
            }
        }
        .frame(minHeight: 30, alignment: .center)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(FacetTheme.canvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(FacetTheme.hairline).frame(height: 1)
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
        .onTapGesture(count: 2) {
            if let date = month.dateForDay(day) {
                createDate = DateWrapper(date: date)
            }
        }
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
            selectedItem: $selectedItem,
            onDoubleTap: { selectItem(item) }
        )
        .help(item.content)
    }

    private func dayBackground(isToday: Bool, hasItems: Bool) -> Color {
        if isToday { return FacetTheme.softAccent }
        if hasItems { return Color.accentColor.opacity(0.035) }
        return Color.clear
    }

    private func selectItem(_ item: ProjectItem) {
        withAnimation(.easeOut(duration: 0.15)) {
            if selectedItem?.id == item.id {
                selectedItem = nil
            } else {
                selectedItem = item
            }
        }
    }

    private func reload() async {
        let requestedMonth = month
        let fetched = await ek.items(forProject: project.prefix,
                                      enabledReminderLists: settings.effectiveReminderListNames,
                                      enabledCalendars: settings.effectiveCalendarNames,
                                      eventStartDate: requestedMonth.startDate,
                                      eventEndDate: requestedMonth.endDate)
        guard !Task.isCancelled, requestedMonth == month else { return }
        if allItems.isEmpty {
            allItems = fetched
        } else {
            withAnimation(listAnimation) {
                allItems = fetched
            }
        }
    }
}


