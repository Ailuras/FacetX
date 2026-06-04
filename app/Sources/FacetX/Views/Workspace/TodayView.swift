import FacetXCore
import SwiftUI

/// Cross-project Today view: item list on the left, compact timeline
/// sidebar on the right when an item is selected.
struct TodayView: View {
    @EnvironmentObject var ek: EventKitService
    @EnvironmentObject var store: ProjectStore
    @EnvironmentObject var settings: AppSettings

    @State private var items: [ProjectItem] = []
    @State private var loading = false
    @State private var searchText = ""
    @State private var refreshTrigger = 0
    @State var selectedItem: ProjectItem? = nil
    @State private var inlineEditingID: String?
    @State private var inlineEditingText: String = ""
    @State private var inlineEditingNotesID: String?
    @State private var inlineEditingNotesText: String = ""
    @State private var draggedItem: ProjectItem?
    @State private var dragSnapshot: [ProjectItem]?

    var listAnimation: Animation { FacetTheme.listSpring }
    var sidebarAnimation: Animation { FacetTheme.detailSpring }

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

    var timelinedItems: [ProjectItem] {
        filteredItems.filter { $0.kind == .event }
    }

    var todayTaskCount: Int {
        allTodayItems.filter { $0.kind == .reminder }.count
    }

    var todayEventCount: Int {
        allTodayItems.filter { $0.kind == .event }.count
    }

    var todayProjectCount: Int {
        Set(allTodayItems.map(\.projectPrefix)).count
    }

    var hasActiveSearch: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: – Body

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                todayInfoBar
                listView
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if selectedItem != nil {
                timelineSidebar
            }
        }
        .animation(sidebarAnimation, value: selectedItem != nil)
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
        }
        .onAppear { Task { await reload() } }
        .task(id: refreshTrigger) { await reload() }
        .onChange(of: store.projects) { Task { await reload() } }
        .onChange(of: ek.remindersAuthorized) { Task { await reload() } }
        .onChange(of: ek.calendarAuthorized) { Task { await reload() } }
        .onChange(of: ek.changeToken) { Task { await reload() } }
        .onChange(of: settings.changeToken) { Task { await reload() } }
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

    // MARK: – List view

    private var todayInfoBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                todaySummaryCluster

                Spacer()

                todayContextCluster
            }

            VStack(alignment: .leading, spacing: 8) {
                todaySummaryCluster

                todayContextCluster
                    .frame(maxWidth: .infinity, alignment: .trailing)
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

    private var todayContextCluster: some View {
        HStack(spacing: 8) {
            if hasActiveSearch {
                searchResultBadge
            }

            timelineRangeBadge
        }
    }

    private var searchResultBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text("\(filteredItems.count) results")
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

    private var timelineRangeBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(timelineRangeLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(FacetTheme.quietPanel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(FacetTheme.hairline, lineWidth: 1)
        )
        .help("Today timeline range")
    }

    private var todaySummaryCluster: some View {
        HStack(spacing: 6) {
            SummaryChip(value: todayTaskCount, label: "Tasks", systemImage: "circle")
            SummaryChip(value: todayEventCount, label: "Events", systemImage: "calendar")
            SummaryChip(value: todayProjectCount, label: "Projects", systemImage: "folder")
        }
    }

    private var timelineRangeLabel: String {
        "\(hourLabel(settings.todayTimelineStartHour))-\(hourLabel(settings.todayTimelineEndHour))"
    }

    private func hourLabel(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
    }

    @ViewBuilder private var listView: some View {
        if filteredItems.isEmpty {
            emptyStateView
        } else {
            List {
                ForEach(filteredItems) { item in
                    todayItemRow(item)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .animation(listAnimation, value: filteredItems.map { "\($0.id)-\($0.isCompleted)" })
        }
    }

    // MARK: – Empty state

    var emptyStateView: some View {
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

    // MARK: – Shared row

    func todayItemRow(_ item: ProjectItem) -> some View {
        ItemRow(
            item: item,
            isSelected: item.id == selectedItem?.id,
            showDragGrip: true,
            onDragStart: {
                ItemDragHelpers.startDrag(
                    item: item,
                    items: items,
                    draggedItem: &draggedItem,
                    dragSnapshot: &dragSnapshot,
                    cancelDrag: {
                        if draggedItem != nil { cancelDrag() }
                    }
                )
            },
            onToggle: { completed in
                Task {
                    await ItemActionHelpers.toggleCompletion(item, completed: completed, ek: ek)
                    await reload()
                }
            },
            onEdit: {
                ItemSelectionHelpers.toggleSelection(item, selectedItem: &selectedItem)
            },
            inlineEditingText: $inlineEditingText,
            isInlineEditing: item.id == inlineEditingID,
            onInlineCommit: {
                commitInlineEdit(for: item)
            },
            onInlineCancel: {
                cancelInlineEdit(for: item)
            },
            inlineEditingNotesText: $inlineEditingNotesText,
            isInlineEditingNotes: item.id == inlineEditingNotesID,
            onInlineNotesCommit: {
                commitInlineNotesEdit(for: item)
            },
            onInlineNotesCancel: {
                cancelInlineNotesEdit(for: item)
            },
            onStartNotesEdit: {
                startInlineNotesEdit(for: item)
            }
        )
        .contextMenu {
            Button("Edit...") {
                ItemSelectionHelpers.toggleSelection(item, selectedItem: &selectedItem)
            }
            Button("Delete", role: .destructive) {
                Task { await ItemActionHelpers.deleteItem(item, ek: ek); await reload() }
            }
        }
        .itemSelectionGestures(
            item: item,
            selectedItem: $selectedItem,
            onDoubleTap: { startInlineEdit(for: item) }
        )
        .onDrop(of: [.text], delegate: ItemDropDelegate(
            item: item,
            draggedItem: $draggedItem,
            onMove: { dragged, target in moveItem(from: dragged, to: target) },
            onDrop: { commitTodayItemOrder(); dragSnapshot = nil }
        ))
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .top)),
            removal: .opacity.combined(with: .scale(scale: 0.98))
        ))
        .opacity(draggedItem?.id == item.id ? 0.32 : 1.0)
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

    func startInlineNotesEdit(for item: ProjectItem) {
        ItemEditHelpers.startNotesEdit(for: item, editingID: &inlineEditingNotesID, editingText: &inlineEditingNotesText)
    }

    func commitInlineNotesEdit(for item: ProjectItem) {
        Task {
            _ = await ItemEditHelpers.commitNotesEdit(
                editingID: inlineEditingNotesID,
                editingText: inlineEditingNotesText,
                for: item,
                projectPrefix: item.projectPrefix,
                ek: ek
            )
            inlineEditingNotesID = nil
            await reload()
        }
    }

    func cancelInlineNotesEdit(for item: ProjectItem) {
        ItemEditHelpers.cancelNotesEdit(editingID: &inlineEditingNotesID)
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

    private func moveItem(from source: ProjectItem, to destination: ProjectItem) {
        guard let fromIndex = items.firstIndex(where: { $0.id == source.id }),
              let toIndex = items.firstIndex(where: { $0.id == destination.id }) else {
            return
        }

        if fromIndex != toIndex {
            withAnimation(.default) {
                let movedItem = items.remove(at: fromIndex)
                items.insert(movedItem, at: toIndex)
            }
        }
    }

    private func commitTodayItemOrder() {
        for project in store.activeProjects {
            let orderedIDs = items
                .filter { $0.projectPrefix == project.prefix }
                .map(\.id)
            guard !orderedIDs.isEmpty else { continue }
            store.setItemOrder(projectID: project.id, orderedIDs: orderedIDs)
        }
    }

    private func cancelDrag() {
        if let snapshot = dragSnapshot {
            withAnimation(listAnimation) { items = snapshot }
        }
        dragSnapshot = nil
        draggedItem = nil
    }
}
