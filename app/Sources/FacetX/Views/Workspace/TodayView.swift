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

    var listAnimation: Animation { FacetTheme.listSpring }
    var sidebarAnimation: Animation { .spring(response: 0.34, dampingFraction: 0.88) }

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
        .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }

    var filteredItems: [ProjectItem] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return allTodayItems }
        return allTodayItems.filter { $0.matches(searchQuery: q) }
    }

    var timelinedItems: [ProjectItem] {
        filteredItems.filter { $0.kind == .event }
    }

    var hasActiveSearch: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: – Body

    var body: some View {
        HStack(spacing: 0) {
            listView
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if selectedItem != nil {
                Divider()
                timelineSidebar
                    .frame(width: 360)
                    .transition(.move(edge: .trailing))
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
        .task { await reload() }
        .task(id: refreshTrigger) { await reload() }
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

    @ViewBuilder private var listView: some View {
        if filteredItems.isEmpty {
            emptyStateView
        } else {
            List {
                ForEach(filteredItems) { item in
                    todayItemRow(item)
                        .listRowBackground(item.id == selectedItem?.id
                                           ? Color.accentColor.opacity(0.08)
                                           : Color.clear)
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
            onEdit: {
                selectedItem = selectedItem?.id == item.id ? nil : item
            },
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
        .onTapGesture {
            selectedItem = selectedItem?.id == item.id ? nil : item
        }
        .listRowSeparator(.hidden)
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
