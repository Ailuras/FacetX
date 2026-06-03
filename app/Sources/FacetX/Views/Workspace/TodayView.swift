import FacetXCore
import SwiftUI

/// Cross-project Today view with List and Timeline modes.
struct TodayView: View {
    @EnvironmentObject var ek: EventKitService
    @EnvironmentObject var store: ProjectStore
    @EnvironmentObject var settings: AppSettings

    let onOpenProject: (Project.ID) -> Void

    @State private var items: [ProjectItem] = []
    @State private var loading = false
    @State private var searchText = ""
    @State private var refreshTrigger = 0
    @State private var selectedItem: ProjectItem? = nil
    @State private var createDate: DateWrapper? = nil
    @State private var inlineEditingID: String?
    @State private var inlineEditingText: String = ""

    var listAnimation: Animation { FacetTheme.listSpring }

    enum ViewMode: String, CaseIterable, Identifiable {
        case list = "List", timeline = "Timeline"
        var id: String { rawValue }
    }

    var viewMode: ViewMode {
        ViewMode(rawValue: settings.todayViewMode) ?? .list
    }

    // MARK: – Derived data

    var projectsByPrefix: [String: Project] {
        Dictionary(store.activeProjects.map { ($0.prefix, $0) }) { first, _ in first }
    }

    var allTodayItems: [ProjectItem] {
        items.filter { item in
            guard let date = item.date else { return false }
            if item.kind == .reminder && item.isCompleted { return false }
            return Calendar.current.isDateInToday(date)
        }
    }

    var filteredItems: [ProjectItem] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return allTodayItems }
        return allTodayItems.filter { $0.matches(searchQuery: q) }
    }

    var hasActiveSearch: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var allDayEvents: [ProjectItem] {
        filteredItems.filter { $0.kind == .event && $0.isAllDay }
    }

    var timedEvents: [ProjectItem] {
        filteredItems.filter { $0.kind == .event && !$0.isAllDay }
    }

    var reminders: [ProjectItem] {
        filteredItems.filter { $0.kind == .reminder }
    }

    var unscheduledReminders: [ProjectItem] {
        reminders.filter { $0.date == nil || Calendar.current.component(.hour, from: $0.date!) == 0 && Calendar.current.component(.minute, from: $0.date!) == 0 }
    }

    var scheduledReminders: [ProjectItem] {
        reminders.filter { !unscheduledReminders.contains($0) }
    }

    func timeSectionItems(hourRange: ClosedRange<Int>) -> [ProjectItem] {
        let cal = Calendar.current
        return (timedEvents + scheduledReminders).filter { item in
            guard let date = item.date else { return false }
            let hour = cal.component(.hour, from: date)
            return hourRange.contains(hour)
        }
    }

    // MARK: – Body

    var body: some View {
        VStack(spacing: 0) {
            switch viewMode {
            case .list: listContent
            case .timeline: timelineContent
            }
        }
        .background(FacetTheme.canvas)
        .navigationTitle("Today")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                ToolbarSearchField(text: $searchText, placeholder: "Search today…")
                    .frame(width: 200, height: 24)
            }
            ToolbarItem(placement: .automatic) {
                refreshButton
            }
            ToolbarItem(placement: .automatic) {
                modePicker
            }
        }
        .task { await reload() }
        .task(id: refreshTrigger) { await reload() }
        .onChange(of: ek.changeToken) { Task { await reload() } }
        .onChange(of: settings.changeToken) { Task { await reload() } }
        .sheet(item: $createDate) { wrapper in
            // For timeline mode, we need to know which project to create in.
            // Default to first active project if only one, otherwise let user choose.
            if let project = defaultProjectForCreation {
                CreateItemView(project: project, initialDate: wrapper.date) {
                    createDate = nil
                    Task { await reload() }
                }
            }
        }
    }

    private var defaultProjectForCreation: Project? {
        let active = store.activeProjects
        if active.count == 1 { return active.first }
        // If multiple, we'll need a project picker - for now return first
        return active.first
    }

    // MARK: – Toolbar

    private var refreshButton: some View {
        Button {
            refreshTrigger &+= 1
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 11, weight: .medium))
        }
        .help("Refresh")
    }

    private var modePicker: some View {
        Picker("", selection: Binding(
            get: { viewMode },
            set: { settings.todayViewMode = $0.rawValue }
        )) {
            ForEach(ViewMode.allCases) { mode in
                Image(systemName: mode == .list ? "list.bullet" : "timeline.selection")
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .help("Switch view mode")
        .frame(width: 80)
    }

    // MARK: – List mode

    @ViewBuilder private var listContent: some View {
        if filteredItems.isEmpty {
            emptyStateView
        } else {
            List {
                if !allDayEvents.isEmpty {
                    Section {
                        ForEach(allDayEvents) { item in
                            todayItemRow(item)
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Image(systemName: "sun.max")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.orange)
                            Text("All-day")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(allDayEvents.count)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                        .textCase(nil)
                    }
                }

                let morning = timeSectionItems(hourRange: 6...11)
                if !morning.isEmpty {
                    timeSection(title: "Morning", systemImage: "sunrise", color: .orange, items: morning)
                }

                let afternoon = timeSectionItems(hourRange: 12...17)
                if !afternoon.isEmpty {
                    timeSection(title: "Afternoon", systemImage: "sun.max", color: .yellow, items: afternoon)
                }

                let evening = timeSectionItems(hourRange: 18...23)
                if !evening.isEmpty {
                    timeSection(title: "Evening", systemImage: "moon", color: .indigo, items: evening)
                }

                if !unscheduledReminders.isEmpty {
                    Section {
                        ForEach(unscheduledReminders) { item in
                            todayItemRow(item)
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Image(systemName: "checklist")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.green)
                            Text("Unscheduled")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(unscheduledReminders.count)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                        .textCase(nil)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .animation(listAnimation, value: filteredItems.map { "\($0.id)-\($0.isCompleted)" })
        }
    }

    private func timeSection(title: String, systemImage: String, color: Color, items: [ProjectItem]) -> some View {
        Section {
            ForEach(items) { item in
                todayItemRow(item)
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(items.count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .textCase(nil)
        }
    }

    @ViewBuilder var emptyStateView: some View {
        ContentUnavailableView {
            Label("Nothing today", systemImage: "checkmark.circle")
        } description: {
            Text(store.activeProjects.isEmpty
                 ? "Create a project to start gathering its items here."
                 : "No items are dated today across your projects.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if loading && items.isEmpty { ProgressView().controlSize(.large) }
        }
    }

    // MARK: – Timeline mode (implemented in TodayView+Timeline.swift)

    // timelineContent, timelineView, etc. are in the extension

    // MARK: – Shared row

    func todayItemRow(_ item: ProjectItem) -> some View {
        let project = projectsByPrefix[item.projectPrefix]
        return ItemRow(
            item: item,
            projectBadge: project?.name ?? item.projectPrefix,
            onToggle: { completed in
                Task {
                    await ItemActionHelpers.toggleCompletion(item, completed: completed, ek: ek)
                    await reload()
                }
            },
            onEdit: { if let project { onOpenProject(project.id) } },
            inlineEditingText: $inlineEditingText,
            isInlineEditing: item.id == inlineEditingID,
            onInlineCommit: {
                commitInlineEdit(for: item)
            },
            onInlineCancel: {
                cancelInlineEdit(for: item)
            }
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            startInlineEdit(for: item)
        }
        .onTapGesture { if let project { onOpenProject(project.id) } }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 3, leading: 14, bottom: 3, trailing: 14))
    }

    // MARK: – Inline editing

    func startInlineEdit(for item: ProjectItem) {
        ItemEditHelpers.startTitleEdit(for: item, editingID: &inlineEditingID, editingText: &inlineEditingText)
    }

    func commitInlineEdit(for item: ProjectItem) {
        Task {
            _ = await ItemEditHelpers.commitTitleEdit(
                editingID: inlineEditingID,
                editingText: inlineEditingText,
                for: item,
                projectPrefix: item.projectPrefix,
                ek: ek
            )
            inlineEditingID = nil
            await reload()
        }
    }

    func cancelInlineEdit(for item: ProjectItem) {
        ItemEditHelpers.cancelTitleEdit(editingID: &inlineEditingID)
    }

    // MARK: – Reload

    func reload() async {
        loading = items.isEmpty
        let prefixes = Set(store.activeProjects.map(\.prefix))
        let fetched = await ek.items(forProjects: prefixes,
                                     enabledReminderLists: settings.effectiveReminderListNames,
                                     enabledCalendars: settings.effectiveCalendarNames)
        if items.isEmpty {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { items = fetched }
        } else {
            withAnimation(listAnimation) { items = fetched }
        }
        loading = false
    }
}
