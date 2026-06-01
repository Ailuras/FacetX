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
        .sheet(item: $createDate) { wrapper in
            CreateItemView(project: project, initialDate: wrapper.date) {
                createDate = nil
                Task { await reload() }
            }
        }
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
                Text(month.id).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button { month = month.shifted(by: 1) } label: { Image(systemName: "chevron.right") }
                .help("Next month")
            Button("This month") { month = MonthYear.containing(Date()) }
                .font(.caption)
                .help("Go to current month")
        }
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
        let isToday = month.isToday(day: day)

        return VStack(alignment: .leading, spacing: 2) {
            Text("\(day)")
                .font(.system(size: 12, weight: isToday ? .bold : .regular))
                .foregroundStyle(isToday ? Color.accentColor : .primary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 4)
                .padding(.trailing, 6)

            VStack(alignment: .leading, spacing: 1) {
                ForEach(items.prefix(3)) { item in
                    dayItemRow(item: item)
                }
                if items.count > 3 {
                    Text("+\(items.count - 3)")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)

            Spacer(minLength: 0)
        }
        .frame(minHeight: 80)
        .background(isToday ? FacetTheme.softAccent : Color.clear)
        .overlay(
            Rectangle()
                .stroke(
                    isToday ? Color.accentColor.opacity(0.4) : FacetTheme.hairline,
                    lineWidth: isToday ? 2 : 0.5
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if let date = month.dateForDay(day) {
                createDate = DateWrapper(date: date)
            }
        }
    }

    private var emptyCell: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(minHeight: 80)
            .overlay(Rectangle().stroke(FacetTheme.hairline, lineWidth: 0.5))
    }

    private func dayItemRow(item: ProjectItem) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(FacetTheme.priorityColor(item.priority))
                .frame(width: 5, height: 5)
            Text(item.content)
                .font(.system(size: 10))
                .lineLimit(1)
                .foregroundStyle(item.isCompleted ? .secondary : .primary)
                .strikethrough(item.isCompleted)
        }
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            selectItem(item)
        }
    }

    private func selectItem(_ item: ProjectItem) {
        withAnimation(.easeOut(duration: 0.15)) { selectedItem = item }
    }

    private func reload() async {
        let requestedMonth = month
        let fetched = await ek.items(forProject: project.prefix,
                                      enabledReminderLists: settings.enabledReminderListNames,
                                      enabledCalendars: settings.enabledCalendarNames,
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

private struct DateWrapper: Identifiable {
    let date: Date

    var id: TimeInterval { date.timeIntervalSinceReferenceDate }
}
