import FacetXCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: AppSettings

    /// Sidebar selection: the cross-project Today view, or one project.
    enum SidebarItem: Hashable { case today, project(Project.ID) }

    @State private var selection: SidebarItem? = .today
    @State private var discovered: [String] = []
    @State private var draftProject: ProjectDraft?
    @State private var editingProject: Project?

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    Section {
                        Label("Today", systemImage: "sun.max.fill")
                            .tag(SidebarItem.today)
                    }
                    Section("Projects") {
                        ForEach(store.activeProjects) { project in
                            ProjectSidebarRow(project: project)
                            .tag(SidebarItem.project(project.id))
                            .contextMenu {
                                Button("Edit Project") {
                                    selection = .project(project.id)
                                    editingProject = project
                                }
                                Divider()
                                Button("Archive") {
                                    store.archive(project)
                                }
                                Button("Delete", role: .destructive) {
                                    store.delete(project)
                                }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                Divider()
                Button { startNewProject() } label: {
                    Label("New Project", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary.opacity(0.82))
                .padding(8)
            }
            .navigationTitle("FacetX")
        } detail: {
            switch selection {
            case .today, nil:
                TodayView(onOpenProject: { selection = .project($0) })
            case .project(let id):
                if let project = store.activeProjects.first(where: { $0.id == id }) {
                    ProjectDetailView(project: project)
                } else {
                    ContentUnavailableView("Select a project",
                        systemImage: "folder",
                        description: Text("Pick a project from the sidebar."))
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .task {
            if !ek.remindersAuthorized && !ek.calendarAuthorized {
                await ek.requestAccess()
            }
            discovered = await ek.discoverProjectNames(
                enabledReminderLists: settings.enabledReminderListNames,
                enabledCalendars: settings.enabledCalendarNames
            )
        }
        .sheet(item: $draftProject) { draft in
            NewProjectView(draft: draft) { name, prefix, tagline, reminderList, calendar in
                let id = store.createProject(name: name, prefix: prefix, tagline: tagline,
                                             reminderListName: reminderList, calendarName: calendar)
                selection = .project(id)
                draftProject = nil
            } onCancel: {
                draftProject = nil
            }
        }
        .sheet(item: $editingProject) { project in
            EditProjectView(project: project) { editingProject = nil }
        }
    }

    private func startNewProject() {
        let existing = Set(store.projects.map(\.name))
        let suggestion = discovered.first { !existing.contains($0) } ?? uniqueProjectName(in: existing)
        let reminderLists = ek.reminderListNames(enabled: settings.enabledReminderListNames)
        let calendars = ek.calendarNames(enabled: settings.enabledCalendarNames)
        draftProject = ProjectDraft(
            name: suggestion,
            prefix: suggestion,
            reminderListName: defaultName(settings.defaultReminderListName, in: reminderLists),
            calendarName: defaultName(settings.defaultCalendarName, in: calendars),
            reminderLists: reminderLists,
            calendars: calendars
        )
    }

    private func uniqueProjectName(in existing: Set<String>) -> String {
        let base = "New Project"
        guard existing.contains(base) else { return base }
        var index = 2
        while existing.contains("\(base) \(index)") { index += 1 }
        return "\(base) \(index)"
    }

    private func defaultName(_ name: String, in options: [String]) -> String {
        options.contains(name) ? name : (options.first ?? "")
    }
}

private struct ProjectSidebarRow: View {
    let project: Project

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                Text(initial)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(project.tagline.isEmpty ? project.prefix : project.tagline)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }

    private var initial: String {
        project.name.trimmingCharacters(in: .whitespacesAndNewlines)
            .first
            .map { String($0).uppercased() } ?? "F"
    }
}

/// Detail pane: a project's items, grouped by container (functional zone).
struct ProjectDetailView: View {
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: AppSettings
    let project: Project

    enum Mode: String, CaseIterable, Identifiable {
        case all = "All", week = "Week"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .all
    @State private var items: [ProjectItem] = []
    @State private var loading = false
    @State private var showCreate = false
    @State private var inlineEditingID: String?
    @State private var inlineEditingText: String = ""
    @State private var inlineEditingNotesID: String?
    @State private var inlineEditingNotesText: String = ""
    @State private var draggedItem: ProjectItem? = nil
    @State private var dragSnapshot: [ProjectItem]? = nil
    @State private var selectedDetailItem: ProjectItem? = nil
    @State private var showCompleted = true
    @State private var searchText = ""

    private var listAnimation: Animation { FacetTheme.listSpring }

    private var visibleItems: [ProjectItem] {
        let base = showCompleted ? items : items.filter { !$0.isCompleted }
        return base.filter { $0.matches(searchQuery: searchText) }
    }

    private var hasActiveSearch: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var grouped: [ItemArrangement.ZoneGroup] {
        ItemArrangement.groupedByZone(visibleItems)
    }

    var body: some View {
        VStack(spacing: 0) {
            projectHeader
            HStack(spacing: 0) {
                Group {
                    switch mode {
                    case .all:  allItemsView
                    case .week: WeekView(project: project, searchText: searchText, showCompleted: showCompleted, selectedItem: $selectedDetailItem)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let selectedItem = selectedDetailItem {
                    Divider()
                    ItemDetailPane(item: selectedItem, project: project, onClose: {
                        selectedDetailItem = nil
                    }, onUpdate: {
                        Task { await reload() }
                    })
                    .frame(width: 340)
                    .transition(.move(edge: .trailing))
                }
            }
        }
        .background(FacetTheme.canvas)
        .navigationTitle(project.name)
        .sheet(isPresented: $showCreate) {
            CreateItemView(project: project) { Task { await reload() } }
        }
        .task(id: project.id) { await reload() }
        .onChange(of: ek.changeToken) { Task { await reload() } }
        .onChange(of: showCompleted) {
            if !showCompleted, selectedDetailItem?.isCompleted == true {
                withAnimation(listAnimation) {
                    selectedDetailItem = nil
                }
            }
        }
    }

    // ── Header controls (mode, search, actions) ──────────────────────────────

    private var rightControls: some View {
        ViewThatFits(in: .horizontal) {
            fullRightControls
            compactRightControls
            minimalRightControls
        }
    }

    private var fullRightControls: some View {
        HStack(spacing: 10) {
            searchField
                .frame(width: 220)
            summaryCluster
            actionCluster
        }
    }

    private var compactRightControls: some View {
        HStack(spacing: 8) {
            searchField
                .frame(width: 180)
            actionCluster
        }
    }

    private var minimalRightControls: some View {
        HStack(spacing: 8) {
            searchField
                .frame(width: 140)
            actionCluster
        }
    }

    private func modePicker(width: CGFloat) -> some View {
        Picker("", selection: $mode) {
            ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .help("Switch view mode")
        .frame(width: width)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search items…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if hasActiveSearch {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(FacetTheme.quietPanel))
        .overlay(Capsule().stroke(FacetTheme.hairline, lineWidth: 1))
    }

    private var actionCluster: some View {
        HStack(spacing: 2) {
            pillButton(systemName: showCompleted ? "checkmark.circle.fill" : "checkmark.circle",
                       help: showCompleted ? "Hide completed reminders" : "Show completed reminders",
                       active: showCompleted) {
                withAnimation(listAnimation) { showCompleted.toggle() }
            }
            pillButton(systemName: "arrow.clockwise", help: "Refresh") {
                Task { await reload() }
            }
            pillButton(systemName: "plus", help: "Add an item to this project") {
                showCreate = true
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(Capsule().fill(FacetTheme.quietPanel))
        .overlay(Capsule().stroke(FacetTheme.hairline, lineWidth: 1))
    }

    private func pillButton(systemName: String, help: String, active: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(active ? Color.accentColor : .secondary)
                .frame(width: 26, height: 24)
                .background(active ? Color.accentColor.opacity(0.14) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder private var allItemsView: some View {
        VStack(spacing: 0) {
            // Keep the List in the tree from the first render and show loading as
            // an overlay. Swapping a ProgressView in/out for the List made the
            // List lay out its rows on first appearance at a bad moment, so the
            // initial open showed crammed rows until a project switch rebuilt it.
            allItemsList
                .overlay {
                    if loading && items.isEmpty {
                        ProgressView().controlSize(.large)
                    }
                }
        }
        .background(FacetTheme.canvas)
    }

    private var allItemsList: some View {
        List {
            if visibleItems.isEmpty && !(loading && items.isEmpty) {
                Section {
                    Text(emptyMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 10)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                ForEach(grouped, id: \.zone) { group in
                    Section {
                        ForEach(group.items) { item in
                            projectItemRow(item)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .top)),
                                    removal: .opacity.combined(with: .scale(scale: 0.98))
                                ))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 3, leading: 14, bottom: 3, trailing: 14))
                        }
                    } header: {
                        Text(group.zone)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                            .padding(.top, 4)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .animation(listAnimation, value: visibleItems.map { "\($0.id)-\($0.isCompleted)" })
    }

    private var emptyMessage: String {
        if hasActiveSearch { return "No items match “\(searchText)”." }
        return items.isEmpty ? "No items yet." : "Completed items are hidden."
    }

    private var projectHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            modePicker(width: 140)

            Spacer(minLength: 14)

            rightControls
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(FacetTheme.canvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(FacetTheme.hairline).frame(height: 1)
        }
    }

    private var summaryCluster: some View {
        HStack(spacing: 6) {
            SummaryChip(value: openItemCount, label: "Open", systemImage: "circle")
            SummaryChip(value: completedReminderCount, label: "Done", systemImage: "checkmark.circle")
            SummaryChip(value: zoneCount, label: "Zones", systemImage: "square.grid.2x2")
        }
    }

    private var openItemCount: Int {
        items.filter { $0.kind == .event || !$0.isCompleted }.count
    }

    private var completedReminderCount: Int {
        items.filter { $0.kind == .reminder && $0.isCompleted }.count
    }

    private var zoneCount: Int {
        Set(items.map(\.containerName)).count
    }

    private func projectItemRow(_ item: ProjectItem) -> some View {
        ItemRow(
            item: item,
            isSelected: item.id == selectedDetailItem?.id,
            showDragGrip: true,
            onDragStart: {
                self.dragSnapshot = items
                self.draggedItem = item

                let timer = Timer(timeInterval: 0.05, repeats: true) { timer in
                    let pressedButtons = NSEvent.pressedMouseButtons
                    let isLeftPressed = (pressedButtons & (1 << 0)) != 0
                    if !isLeftPressed {
                        timer.invalidate()
                        Task { @MainActor in
                            if self.draggedItem != nil {
                                self.cancelDrag()
                            }
                        }
                    }
                }
                RunLoop.main.add(timer, forMode: .common)

                return NSItemProvider(object: item.id as NSString)
            },
            onToggle: { completed in
                Task {
                    await ek.setReminderCompleted(id: item.id, completed: completed)
                    await reload()
                }
            },
            onEdit: {
                withAnimation(.easeOut(duration: 0.15)) { selectedDetailItem = item }
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
                withAnimation(.easeOut(duration: 0.15)) { selectedDetailItem = item }
            }
            Button("Delete", role: .destructive) {
                Task { _ = await ek.deleteItem(id: item.id); await reload() }
            }
        }
        .onTapGesture(count: 2) {
            startInlineEdit(for: item)
        }
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.15)) {
                selectedDetailItem = item
            }
        }
        .onDrop(of: [.text], delegate: ItemDropDelegate(
            item: item,
            draggedItem: $draggedItem,
            onMove: { dragged, target in moveItem(from: dragged, to: target) },
            onDrop: { commitItemOrder(); dragSnapshot = nil }
        ))
        .opacity(draggedItem?.id == item.id ? 0.32 : 1.0)
    }

    private func startInlineEdit(for item: ProjectItem) {
        inlineEditingText = item.content
        inlineEditingID = item.id
    }

    private func commitInlineEdit(for item: ProjectItem) {
        guard inlineEditingID == item.id else { return }
        let newContent = inlineEditingText.trimmingCharacters(in: .whitespaces)
        inlineEditingID = nil

        Task {
            if newContent.isEmpty {
                _ = await ek.deleteItem(id: item.id)
            } else if newContent != item.content {
                _ = await ek.updateItem(id: item.id, project: project.prefix, content: newContent,
                                        date: item.date, useDate: item.date != nil,
                                        containerName: item.containerName, notes: item.notes,
                                        priority: item.priority)
            }
            await reload()
        }
    }

    private func cancelInlineEdit(for item: ProjectItem) {
        guard inlineEditingID == item.id else { return }
        inlineEditingID = nil
        Task { await reload() }
    }

    private func startInlineNotesEdit(for item: ProjectItem) {
        inlineEditingNotesText = item.notes ?? ""
        inlineEditingNotesID = item.id
    }

    private func commitInlineNotesEdit(for item: ProjectItem) {
        guard inlineEditingNotesID == item.id else { return }
        let newNotes = inlineEditingNotesText.trimmingCharacters(in: .whitespacesAndNewlines)
        inlineEditingNotesID = nil
        
        let notesParam = newNotes.isEmpty ? nil : newNotes
        Task {
            if notesParam != item.notes {
                _ = await ek.updateItem(id: item.id, project: project.prefix, content: item.content,
                                        date: item.date, useDate: item.date != nil,
                                        containerName: item.containerName, notes: notesParam,
                                        priority: item.priority)
            }
            await reload()
        }
    }

    private func cancelInlineNotesEdit(for item: ProjectItem) {
        guard inlineEditingNotesID == item.id else { return }
        inlineEditingNotesID = nil
        Task { await reload() }
    }

    private func reload() async {
        loading = items.isEmpty
        let fetched = await ek.items(forProject: project.prefix,
                                     enabledReminderLists: settings.enabledReminderListNames,
                                     enabledCalendars: settings.enabledCalendarNames)
        store.pruneItemOrder(projectID: project.id, keeping: Set(fetched.map(\.id)))
        let sortedItems = ItemArrangement.arranged(fetched, savedOrder: project.itemOrder ?? [])
        let selectedId = selectedDetailItem?.id
        let firstPopulation = items.isEmpty

        let apply = {
            items = sortedItems
            if let selectedId {
                // Keep the selection only if it's still visible under the
                // current completed/search filters; otherwise drop the pane.
                selectedDetailItem = visibleItems.first { $0.id == selectedId }
            }
        }

        if firstPopulation {
            // First population: skip the row insertion animation so the rows
            // don't fly in from the top and momentarily pile up.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction, apply)
        } else {
            withAnimation(listAnimation, apply)
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

    /// Persist the current in-memory item order. Called once when the drag is
    /// released, not on every drag-over (which would write to disk repeatedly).
    private func commitItemOrder() {
        store.setItemOrder(projectID: project.id, orderedIDs: items.map(\.id))
    }

    private func cancelDrag() {
        if let snapshot = dragSnapshot {
            withAnimation(listAnimation) { items = snapshot }
        }
        dragSnapshot = nil
        draggedItem = nil
    }
}
