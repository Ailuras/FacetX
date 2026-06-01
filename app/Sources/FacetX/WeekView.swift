import FacetXCore
import SwiftUI

/// Single-project week view: a time-focused slice — this week's goal (backed by
/// a week-spanning EventKit event) plus the project's items grouped by day.
struct WeekView: View {
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: AppSettings

    let project: Project
    let searchText: String
    let showCompleted: Bool
    /// The item shown in the shared detail pane (owned by ProjectDetailView), so
    /// week-view edits open the same side pane as the all-items view.
    @Binding var selectedItem: ProjectItem?

    @State private var week = ISOWeek.containing(Date())
    @State private var allItems: [ProjectItem] = []
    @State private var loading = false
    @State private var editingGoal = false
    @State private var goalTitle = ""
    @State private var goalBody = ""
    @State private var savingGoal = false
    @State private var goalError: String?

    private var listAnimation: Animation { FacetTheme.listSpring }

    // MARK: - Derived data

    private var weekItems: [ProjectItem] {
        var items = ItemArrangement.inWeek(allItems, week)
        if !showCompleted {
            items = items.filter { !$0.isCompleted }
        }
        return items.filter { $0.matches(searchQuery: searchText) }
    }

    /// Exclude the goal event from the day list so it doesn't appear twice.
    private var nonGoalItems: [ProjectItem] {
        let goalEventId = goal?.eventId
        return weekItems.filter { item in
            if item.id == goalEventId { return false }
            guard case .event = item.kind else { return true }
            return !WeekGoalEvent.isGoalContent(item.content)
        }
    }

    private var hasActiveSearch: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var goal: WeekGoal? {
        store.weekGoal(projectID: project.id, weekId: week.id)
    }

    private var dayGroups: [DayGroup] {
        let cal = Calendar(identifier: .iso8601)
        var groups: [DayGroup] = []

        for offset in 0..<7 {
            guard let date = cal.date(byAdding: .day, value: offset, to: week.startDate) else { continue }
            let dayItems = nonGoalItems.filter { item in
                guard let d = item.date else { return false }
                return cal.isDate(d, inSameDayAs: date)
            }

            let wd = DateFormatter()
            wd.dateFormat = "EEE"
            let weekdayLabel = wd.string(from: date)

            let df = DateFormatter()
            df.dateFormat = "MMM d"
            let dateLabel = df.string(from: date)

            groups.append(DayGroup(
                date: date,
                label: "\(weekdayLabel), \(dateLabel)",
                weekdayLabel: weekdayLabel,
                items: dayItems,
                isToday: cal.isDateInToday(date)
            ))
        }
        return groups
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            weekNav
            VStack(alignment: .leading, spacing: 14) {
                goalSection
                itemsSection
                Spacer()
            }
            .padding(16)
        }
        .background(FacetTheme.canvas)
        .task(id: project.id) { await reload() }
        .onChange(of: ek.changeToken) { Task { await reload() } }
    }

    // MARK: - Week navigation

    private var weekNav: some View {
        HStack {
            Button { week = week.shifted(by: -1) } label: { Image(systemName: "chevron.left") }
                .help("Previous week")
            Spacer()
            VStack(spacing: 2) {
                Text(week.label).font(.headline)
                Text(week.id).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button { week = week.shifted(by: 1) } label: { Image(systemName: "chevron.right") }
                .help("Next week")
            Button("This week") { week = ISOWeek.containing(Date()) }
                .font(.caption)
                .help("Go to current week")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(FacetTheme.canvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(FacetTheme.hairline).frame(height: 1)
        }
    }

    // MARK: - Goal

    @ViewBuilder private var goalSection: some View {
        if editingGoal {
            VStack(alignment: .leading, spacing: 6) {
                Text("Weekly goal").font(.caption).foregroundStyle(.secondary)
                TextField("This week I'm focused on…", text: $goalTitle)
                    .textFieldStyle(.roundedBorder)
                TextField("Details (optional)", text: $goalBody, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(2...4)
                if let goalError {
                    Text(goalError).font(.caption).foregroundStyle(.red)
                }
                HStack {
                    Button("Save") {
                        Task { await saveGoal() }
                    }
                    .disabled(savingGoal)
                    if savingGoal { ProgressView().scaleEffect(0.7) }
                    Button("Cancel") { editingGoal = false }
                        .disabled(savingGoal)
                }
            }
            .padding(12)
            .background(FacetTheme.quietPanel)
            .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                    .stroke(FacetTheme.hairline, lineWidth: 1)
            )
        } else if let goal {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label("Weekly goal", systemImage: "target")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Edit") { startEditingGoal() }
                        .font(.caption)
                        .help("Edit weekly goal")
                }
                Text(goal.title).font(.title3).bold()
                if !goal.body.isEmpty {
                    Text(goal.body).font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(FacetTheme.quietPanel)
            .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                    .stroke(FacetTheme.hairline, lineWidth: 1)
            )
        } else {
            Button { startEditingGoal() } label: {
                Label("Set this week's goal", systemImage: "plus.circle")
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .help("Set this week's project goal")
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FacetTheme.quietPanel)
            .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                    .stroke(FacetTheme.hairline, lineWidth: 1)
            )
        }
    }

    // MARK: - Items grouped by day

    @ViewBuilder private var itemsSection: some View {
        if loading {
            ProgressView()
        } else if nonGoalItems.isEmpty && hasActiveSearch {
            Text("No items match this search.")
                .font(.callout).foregroundStyle(.secondary)
        } else if nonGoalItems.isEmpty && !hasActiveSearch {
            Text("No items this week.")
                .font(.callout).foregroundStyle(.secondary)
        } else {
            List {
                ForEach(dayGroups) { group in
                    Section {
                        if group.items.isEmpty {
                            Text("No items")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .padding(.vertical, 4)
                        } else {
                            ForEach(group.items) { item in
                                ItemRow(
                                    item: item,
                                    isSelected: item.id == selectedItem?.id,
                                    showDragGrip: false,
                                    onToggle: { completed in
                                        Task {
                                            await ek.setReminderCompleted(id: item.id, completed: completed)
                                            await reload()
                                        }
                                    },
                                    onEdit: {
                                        selectItem(item)
                                    }
                                )
                                .contextMenu {
                                    Button("Edit...") { selectItem(item) }
                                    Button("Delete", role: .destructive) {
                                        Task { _ = await ek.deleteItem(id: item.id); await reload() }
                                    }
                                }
                                .onTapGesture { selectItem(item) }
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .top)),
                                    removal: .opacity.combined(with: .scale(scale: 0.98))
                                ))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                            }
                        }
                    } header: {
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
                        }
                        .textCase(nil)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .animation(listAnimation, value: nonGoalItems.map { "\($0.id)-\($0.isCompleted)" })
        }
    }

    // MARK: - Helpers

    private func selectItem(_ item: ProjectItem) {
        withAnimation(.easeOut(duration: 0.15)) { selectedItem = item }
    }

    private func startEditingGoal() {
        goalTitle = goal?.title ?? ""
        goalBody = goal?.body ?? ""
        goalError = nil
        editingGoal = true
    }

    /// Saves or deletes the goal, keeping the week-spanning EventKit event in sync.
    private func saveGoal() async {
        guard !savingGoal else { return }
        savingGoal = true
        goalError = nil
        defer { savingGoal = false }

        let trimmed = goalTitle.trimmingCharacters(in: .whitespaces)
        let currentWeek = week // copy to avoid sending main-actor state to nonisolated method

        if trimmed.isEmpty {
            if let eventId = goal?.eventId {
                let deleted = await ek.deleteGoalEvent(eventId: eventId)
                guard deleted else {
                    goalError = "Could not delete the calendar event. Check Calendar access."
                    return
                }
            }
            store.setWeekGoal(projectID: project.id, weekId: currentWeek.id, title: "", body: "")
        } else {
            let eventId = await ek.createOrUpdateGoalEvent(
                project: project.prefix,
                title: trimmed,
                body: goalBody,
                week: currentWeek,
                calendarName: project.calendarName,
                existingEventId: goal?.eventId,
                enabledCalendars: settings.enabledCalendarNames
            )
            guard let eventId else {
                goalError = "Could not save the calendar event. Check Calendar access and enabled calendars."
                return
            }
            store.setWeekGoal(
                projectID: project.id,
                weekId: currentWeek.id,
                title: goalTitle,
                body: goalBody,
                eventId: eventId
            )
        }

        editingGoal = false
        await reload()
    }

    private func reload() async {
        loading = allItems.isEmpty
        let fetched = await ek.items(forProject: project.prefix,
                                     enabledReminderLists: settings.enabledReminderListNames,
                                     enabledCalendars: settings.enabledCalendarNames)
        if allItems.isEmpty {
            allItems = fetched
        } else {
            withAnimation(listAnimation) {
                allItems = fetched
            }
        }
        loading = false
    }
}

// MARK: - Day group model

private struct DayGroup: Identifiable {
    let date: Date
    let label: String
    let weekdayLabel: String
    let items: [ProjectItem]
    let isToday: Bool

    var id: Date { date }
}
