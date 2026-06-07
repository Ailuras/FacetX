import AppKit
import FacetXCore
import SwiftUI

struct ProjectDetailView: View {
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var keyboard: KeyboardActionRouter
    let project: Project
    let showTodayPanel: Binding<Bool>
    @Binding var selectedTag: String?

    enum Mode: String, CaseIterable, Identifiable {
        case all = "All", week = "Week", month = "Month", commits = "Git"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .all
    @State private var items: [ProjectItem] = []
    @State private var loading = false
    @State private var inlineEdit = ItemInlineEditState()
    @State private var draggedItem: ProjectItem? = nil
    @State private var dragSnapshot: [ProjectItem]? = nil
    @State private var selectedDetailItem: ProjectItem? = nil
    @State private var focusTitleItemID: String? = nil
    @State private var preserveSelectionDuringReplacement = false
    @State private var showCompleted = true
    @State private var searchText = ""
    @State private var itemToDelete: ProjectItem? = nil
    @State private var refreshTrigger = 0
    @State private var sortOption: SortOption = .manual
    @State private var kindFilter: ProjectItem.Kind? = nil

    private var listAnimation: Animation { FacetTheme.listSpring }
    private var detailPaneAnimation: Animation { FacetTheme.detailSpring }

    private var visibleItems: [ProjectItem] {
        var result = items
        if let tag = selectedTag {
            result = ItemQuery.filteredByTag(result, tag: tag)
        }
        if let kind = kindFilter {
            result = ItemQuery.filteredByKind(result, kind: kind)
        }
        result = ItemQuery.completedVisibility(result, showCompleted: showCompleted)
        result = ItemQuery.searched(result, query: searchText)
        return ItemArrangement.sorted(result, by: sortOption, savedOrder: project.itemOrder)
    }

    private var hasActiveSearch: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var taskItems: [ProjectItem] {
        visibleItems.filter { $0.kind == .reminder }
    }

    private var scheduleItems: [ProjectItem] {
        visibleItems.filter { $0.kind == .event }
    }

    private var itemCounts: ItemCounts {
        ItemQuery.counts(for: items)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Group {
                    switch mode {
                    case .all: allItemsView
                    case .week: WeekView(project: project, searchText: searchText, showCompleted: showCompleted, selectedItem: $selectedDetailItem, selectedTag: $selectedTag, refreshTrigger: refreshTrigger, onCreateItem: beginCreate)
                    case .month: MonthView(project: project, searchText: searchText, showCompleted: showCompleted, selectedItem: $selectedDetailItem, selectedTag: $selectedTag, refreshTrigger: refreshTrigger, onCreateItem: beginCreate)
                    case .commits: CommitsView(project: project, searchText: searchText, refreshTrigger: refreshTrigger)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let selectedItem = selectedDetailItem {
                    detailPane(for: selectedItem)
                }
            }
            .animation(detailPaneAnimation, value: selectedDetailItem != nil)
        }
        .background(FacetTheme.canvas)
        .navigationTitle(project.name)
        .toolbar {
            ToolbarItem(placement: .status) {
                modePicker(width: 200)
            }
            ToolbarItem(placement: .automatic) {
                ToolbarSearchField(text: $searchText, placeholder: mode == .commits ? "Search commits…" : "Search items…")
                    .frame(width: 220, height: 24)
            }
            ToolbarItem(placement: .primaryAction) {
                toolbarActions
            }
        }
        .task(id: project.id) { await reload() }
        .onChange(of: ek.changeToken) { Task { await reload() } }
        .onChange(of: settings.changeToken) { Task { await reload() } }
        .onChange(of: showCompleted) {
            if !showCompleted, selectedDetailItem?.isCompleted == true {
                withAnimation(detailPaneAnimation) {
                    selectedDetailItem = nil
                }
            }
        }
        .onChange(of: mode) {
            withAnimation(detailPaneAnimation) {
                selectedDetailItem = nil
                preserveSelectionDuringReplacement = false
            }
        }
        .onChange(of: selectedTag) {
            if let item = selectedDetailItem, !visibleItems.contains(where: { $0.id == item.id }) {
                withAnimation(detailPaneAnimation) {
                    selectedDetailItem = nil
                }
            }
        }
        .onChange(of: selectedDetailItem) { _, newItem in
            if newItem != nil {
                showTodayPanel.wrappedValue = false
            } else {
                focusTitleItemID = nil
                preserveSelectionDuringReplacement = false
            }
        }
        .onChange(of: showTodayPanel.wrappedValue) { _, newValue in
            if newValue, selectedDetailItem != nil {
                withAnimation(detailPaneAnimation) {
                    selectedDetailItem = nil
                    preserveSelectionDuringReplacement = false
                }
            }
        }
        .onReceive(keyboard.commandPublisher) { cmd in
            switch cmd {
            case .modeAll:     mode = .all
            case .modeWeek:    mode = .week
            case .modeMonth:   mode = .month
            case .modeGit:     mode = .commits
            case .newItem:     beginCreate()
            case .refresh:
                refreshTrigger += 1
                toast.show("Refreshed", type: .success, duration: 1.5)
            case .toggleShowCompleted:
                withAnimation(listAnimation) { showCompleted.toggle() }
            case .focusSearch:
                NotificationCenter.default.post(name: .focusSearchField, object: nil)
            case .toggleCompletion:
                guard let item = selectedDetailItem else { return }
                Task {
                    await ItemActionHelpers.toggleCompletion(item, completed: !item.isCompleted, ek: ek)
                    await reload()
                }
            case .openDetail:
                guard selectedDetailItem == nil, let first = visibleItems.first else { return }
                withAnimation(detailPaneAnimation) { selectedDetailItem = first }
            case .closeDetail:
                guard selectedDetailItem != nil else { return }
                withAnimation(detailPaneAnimation) {
                    selectedDetailItem = nil
                    preserveSelectionDuringReplacement = false
                }
            case .editSelectedItemTitle:
                guard mode == .all, let item = selectedDetailItem else { return }
                inlineEdit.startTitleEdit(for: item)
            case .deleteItem:
                guard selectedDetailItem != nil else { return }
                itemToDelete = selectedDetailItem
            default:
                break
            }
        }
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

    private func detailPane(for selectedItem: ProjectItem) -> some View {
        FacetSidebarPane(
            title: selectedItem.kind == .reminder ? "Reminder" : "Event",
            systemImage: selectedItem.kind == .reminder ? "checklist" : "calendar",
            subtitle: selectedItem.content,
            onClose: {
                withAnimation(detailPaneAnimation) {
                    selectedDetailItem = nil
                    preserveSelectionDuringReplacement = false
                }
            }
        ) {
            ItemDetailPane(item: selectedItem,
                           project: project,
                           focusTitleOnAppear: selectedItem.id == focusTitleItemID,
                           onClose: {
                withAnimation(detailPaneAnimation) {
                    selectedDetailItem = nil
                }
            }, onReplacementStart: {
                preserveSelectionDuringReplacement = true
            }, onUpdate: { selectionID in
                Task {
                    if selectionID != nil {
                        refreshTrigger += 1
                    }
                    await reload(selecting: selectionID, endingReplacement: selectionID != nil)
                }
            })
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

    @EnvironmentObject private var toast: ToastController

    private var todayButton: some View {
        Button {
            withAnimation(FacetTheme.detailSpring) { showTodayPanel.wrappedValue.toggle() }
        } label: {
            Image(systemName: showTodayPanel.wrappedValue ? "sun.max.fill" : "sun.max")
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 13, weight: .medium))
        }
        .help(showTodayPanel.wrappedValue ? "Hide Today panel" : "Show Today timeline")
    }

    private var refreshButton: some View {
        Button {
            refreshTrigger += 1
            toast.show("Refreshed", type: .success, duration: 1.5)
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 11, weight: .medium))
        }
        .help("Refresh")
    }

    private var toolbarActions: some View {
        HStack(spacing: 3) {
            todayButton
            refreshButton
        }
    }

    private var actionCluster: some View {
        HStack(spacing: 2) {
            pillButton(systemName: showCompleted ? "checkmark.circle.fill" : "checkmark.circle",
                       help: showCompleted ? "Hide completed reminders" : "Show completed reminders",
                       active: showCompleted) {
                withAnimation(listAnimation) { showCompleted.toggle() }
            }
            pillButton(systemName: "plus", help: "Add an item to this project") {
                beginCreate()
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
        )
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
            allViewInfoBar

            allItemsList
                .overlay {
                    if loading && items.isEmpty {
                        ProgressView().controlSize(.large)
                    }
                }
        }
        .background(FacetTheme.canvas)
        .onChange(of: refreshTrigger) { Task { await reload() } }
    }

    private var allViewInfoBar: some View {
        HStack(spacing: 12) {
            summaryCluster

            kindFilterPicker

            if let tag = selectedTag {
                tagFilterChip(tag)
            }

            Spacer()

            if hasActiveSearch {
                FacetInfoBadge(
                    text: "\(visibleItems.count) results",
                    systemImage: "magnifyingglass",
                    tint: .secondary,
                    fill: Color.accentColor.opacity(0.08)
                )
            }

            if !showCompleted && completedReminderCount > 0 {
                FacetInfoBadge(
                    text: "\(completedReminderCount) hidden",
                    systemImage: "eye.slash",
                    tint: .secondary,
                    fill: Color.orange.opacity(0.08)
                )
            }

            sortMenu

            actionCluster
        }
        .frame(minHeight: 30, alignment: .center)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(FacetTheme.canvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(FacetTheme.hairline).frame(height: 1)
        }
    }

    private func tagFilterChip(_ tag: String) -> some View {
        let color = settings.tagColor(for: tag)
        return Button {
            selectedTag = nil
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 9, weight: .semibold))
                Text(tag)
                    .font(.system(size: 11, weight: .semibold))
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(color.opacity(0.30), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("Clear tag filter")
    }

    private var kindFilterPicker: some View {
        Picker("", selection: $kindFilter) {
            Text("All").tag(nil as ProjectItem.Kind?)
            Text("Tasks").tag(ProjectItem.Kind.reminder as ProjectItem.Kind?)
            Text("Events").tag(ProjectItem.Kind.event as ProjectItem.Kind?)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 160)
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SortOption.allCases) { option in
                Button {
                    sortOption = option
                } label: {
                    HStack {
                        Text(option.rawValue)
                        if sortOption == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: sortOption.systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 24)
                .background(Color.accentColor.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Sort: \(sortOption.rawValue)")
    }

    private var allItemsList: some View {
        Group {
            if visibleItems.isEmpty && !(loading && items.isEmpty) {
                emptyAllItemsView
            } else {
                List {
                    itemKindSection(title: "Tasks", systemImage: "checklist",
                                    count: taskItems.count, color: .green, items: taskItems)
                    itemKindSection(title: "Schedule", systemImage: "calendar",
                                    count: scheduleItems.count, color: .blue, items: scheduleItems)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var emptyAllItemsView: some View {
        ContentUnavailableView {
            Label(emptyTitle, systemImage: hasActiveSearch ? "magnifyingglass" : "checkmark.circle")
        } description: {
            Text(emptyMessage)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyTitle: String {
        if hasActiveSearch { return "No results" }
        return items.isEmpty ? "No items yet" : "Completed items hidden"
    }

    @ViewBuilder private func itemKindSection(title: String, systemImage: String,
                                              count: Int, color: Color,
                                              items: [ProjectItem]) -> some View {
        if !items.isEmpty {
            itemKindHeader(title: title, systemImage: systemImage, count: count, color: color)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 14, leading: 14, bottom: 4, trailing: 14))

            ForEach(items) { item in
                projectItemRow(item)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 3, leading: 14, bottom: 3, trailing: 14))
            }
        }
    }

    private func itemKindHeader(title: String, systemImage: String, count: Int, color: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Text("\(count)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color.opacity(0.12))
                .clipShape(Capsule())
            Spacer()
        }
        .foregroundStyle(.primary.opacity(0.86))
    }

    private var emptyMessage: String {
        if hasActiveSearch { return "No items match “\(searchText)”." }
        return items.isEmpty ? "No items yet." : "Completed items are hidden."
    }

    private var summaryCluster: some View {
        HStack(spacing: 6) {
            SummaryChip(value: openTaskCount, label: "Tasks", systemImage: "circle")
            SummaryChip(value: eventCount, label: "Events", systemImage: "calendar")
            SummaryChip(value: completedReminderCount, label: "Done", systemImage: "checkmark.circle")
        }
    }

    private var openTaskCount: Int {
        itemCounts.openReminderCount
    }

    private var eventCount: Int {
        itemCounts.eventCount
    }

    private var completedReminderCount: Int {
        itemCounts.completedReminderCount
    }

    private func projectItemRow(_ item: ProjectItem) -> some View {
        StandardItemRow(
            item: item,
            projectPrefix: project.prefix,
            selectedItem: $selectedDetailItem,
            inlineEdit: $inlineEdit,
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
            onReload: {
                await reload()
            },
            onDeleteRequest: { item in
                itemToDelete = item
            }
        )
        .onDrop(of: [.text], delegate: ItemDropDelegate(
            item: item,
            draggedItem: $draggedItem,
            onMove: { dragged, target in moveItem(from: dragged, to: target) },
            onDrop: { commitItemOrder(); dragSnapshot = nil }
        ))
        .opacity(draggedItem?.id == item.id ? 0.32 : 1.0)
    }

    private func reload(
        selecting selectionID: String? = nil,
        focusTitle: Bool = false,
        endingReplacement: Bool = false
    ) async {
        loading = items.isEmpty
        let fetched = await ek.items(forProject: project.prefix,
                                     enabledReminderLists: settings.effectiveReminderListNames,
                                     enabledCalendars: settings.effectiveCalendarNames)
        store.pruneItemOrder(projectID: project.id, keeping: Set(fetched.map(\.id)))
        let sortedItems = ItemArrangement.arranged(fetched, savedOrder: project.itemOrder)
        let selectedId = selectionID ?? selectedDetailItem?.id
        let firstPopulation = items.isEmpty

        let apply = {
            items = sortedItems
            store.reportTags(projectID: project.id, items: sortedItems)
            if let selectedId {
                if let refreshedSelection = sortedItems.first(where: { $0.id == selectedId }) {
                    selectedDetailItem = refreshedSelection
                } else if selectionID != nil || !preserveSelectionDuringReplacement {
                    selectedDetailItem = nil
                }
                if focusTitle, selectedDetailItem?.id == selectedId {
                    focusTitleItemID = selectedId
                }
            }
            if endingReplacement {
                preserveSelectionDuringReplacement = false
            }
        }

        if firstPopulation {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction, apply)
        } else {
            withAnimation(listAnimation, apply)
        }
        loading = false
    }

    private func beginCreate(initialDate: Date? = nil) {
        let listName = settings.reminderSaveTarget(projectListName: project.reminderListName)
        guard !listName.isEmpty else {
            toast.show("Choose a reminder list first", type: .error)
            return
        }
        Task {
            let dueDate = initialDate.map { FacetDateDefaults.dayDefault(reference: $0) }
            guard let id = await ek.createReminder(
                project: project.prefix,
                content: "New Todo",
                listName: listName,
                dueDate: dueDate,
                dueIncludesTime: false,
                enabledLists: settings.effectiveReminderListNames
            ) else {
                toast.show("Could not create item", type: .error)
                return
            }
            refreshTrigger += 1
            await reload(selecting: id, focusTitle: true)
        }
    }

    private func moveItem(from source: ProjectItem, to destination: ProjectItem) {
        guard let fromIndex = items.firstIndex(where: { $0.id == source.id }),
              let toIndex = items.firstIndex(where: { $0.id == destination.id }) else {
            return
        }

        if fromIndex != toIndex {
            withAnimation(FacetTheme.dragPreviewAnimation) {
                let movedItem = items.remove(at: fromIndex)
                items.insert(movedItem, at: toIndex)
            }
        }
    }

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
