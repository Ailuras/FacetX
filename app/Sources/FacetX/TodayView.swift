import FacetXCore
import SwiftUI

/// Cross-project Today view: a single flat list of everything across all
/// projects whose date is today. Reads straight from EventKit (no new storage)
/// and tags each row with its owning project; tapping a row jumps to that
/// project so it can be edited there.
struct TodayView: View {
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: AppSettings

    /// Jump to a project in the sidebar when a row is tapped.
    let onOpenProject: (Project.ID) -> Void

    @State private var items: [ProjectItem] = []
    @State private var loading = false
    @State private var inlineEditingID: String?
    @State private var inlineEditingText: String = ""

    private var listAnimation: Animation { FacetTheme.listSpring }

    /// Map a claimed prefix to its project, for the row badge and tap target.
    private var projectsByPrefix: [String: Project] {
        Dictionary(store.activeProjects.map { ($0.prefix, $0) }) { first, _ in first }
    }

    /// Items dated today, across projects. Completed reminders drop out.
    private var todayItems: [ProjectItem] {
        items.filter { item in
            guard let date = item.date else { return false }
            if item.kind == .reminder && item.isCompleted { return false }
            return Calendar.current.isDateInToday(date)
        }
        .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }

    var body: some View {
        content
        .background(FacetTheme.canvas)
        .navigationTitle("Today")
        .task { await reload() }
        .onChange(of: ek.changeToken) { Task { await reload() } }
        .onChange(of: settings.changeToken) { Task { await reload() } }
    }

    @ViewBuilder private var content: some View {
        if todayItems.isEmpty {
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
        } else {
            List {
                ForEach(todayItems) { item in row(item) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .animation(listAnimation, value: todayItems.map { "\($0.id)-\($0.isCompleted)" })
        }
    }

    private func row(_ item: ProjectItem) -> some View {
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

    private func startInlineEdit(for item: ProjectItem) {
        ItemEditHelpers.startTitleEdit(for: item, editingID: &inlineEditingID, editingText: &inlineEditingText)
    }

    private func commitInlineEdit(for item: ProjectItem) {
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

    private func cancelInlineEdit(for item: ProjectItem) {
        ItemEditHelpers.cancelTitleEdit(editingID: &inlineEditingID)
    }

    private func reload() async {
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
