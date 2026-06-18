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
    @Binding var tagFilter: TagFilter

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
    @State private var itemFilter = ItemListFilter()
    @State private var noteStore = ItemStore.shared

    private var listAnimation: Animation { FacetTheme.listSpring }
    private var detailPaneAnimation: Animation { FacetTheme.detailSpring }

    private var allScopedItems: [ProjectItem] {
        var result = ItemQuery.filtered(items, by: tagFilter)
        result = ItemQuery.filtered(result, by: itemFilter)
        return ItemQuery.searched(result, query: searchText)
    }

    private var visibleItems: [ProjectItem] {
        let result = ItemQuery.completedVisibility(allScopedItems, showCompleted: showCompleted)
        // Manual order is already applied in items by reload()/moveItem(); re-sorting
        // here via arranged() would snap drag-reordered rows back to the saved rank.
        guard sortOption != .manual else { return result }
        return ItemArrangement.sorted(result, by: sortOption, savedOrder: project.itemOrder)
    }

    private var hasActiveSearch: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var taskItems: [ProjectItem] {
        visibleItems.filter { $0.kind == .reminder }
    }

    private var scheduleItems: [ProjectItem] {
        visibleItems.filter { $0.kind == .event && $0.linkedPaperIDs.isEmpty }
    }

    private var literatureItems: [ProjectItem] {
        visibleItems.filter { $0.kind == .event && !$0.linkedPaperIDs.isEmpty }
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
                    case .week: WeekView(project: project, searchText: searchText, showCompleted: $showCompleted, selectedItem: $selectedDetailItem, tagFilter: $tagFilter, itemFilter: $itemFilter, refreshTrigger: refreshTrigger, onCreateItem: beginCreate)
                    case .month: MonthView(project: project, searchText: searchText, showCompleted: $showCompleted, selectedItem: $selectedDetailItem, tagFilter: $tagFilter, itemFilter: $itemFilter, refreshTrigger: refreshTrigger, onCreateItem: beginCreate)
                    case .commits:
                        CommitsView(project: project, items: items, searchText: searchText, refreshTrigger: refreshTrigger) {
                            await reload()
                        }
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
                modePicker
            }
            ToolbarItem(placement: .automatic) {
                ToolbarSearchField(text: $searchText, placeholder: mode == .commits ? L10n.t(.searchCommits) : L10n.t(.searchItems))
                    .frame(width: 220, height: 24)
            }
            ToolbarItem(placement: .primaryAction) {
                toolbarActions
            }
        }
        .task(id: project.id) { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .selectItemInProjectDetail)) { notification in
            guard let itemID = notification.userInfo?["itemID"] as? String else { return }
            if let target = items.first(where: { $0.id == itemID }) {
                selectedDetailItem = target
            }
        }
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
        .onChange(of: tagFilter) {
            if let item = selectedDetailItem, !visibleItems.contains(where: { $0.id == item.id }) {
                withAnimation(detailPaneAnimation) {
                    selectedDetailItem = nil
                }
            }
        }
        .onChange(of: itemFilter) {
            if selectedDetailItem != nil {
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
                toast.show(L10n.t(.refreshed), type: .success, duration: 1.5)
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
        .alert(L10n.t(.deleteItemTitle), isPresented: .init(
            get: { itemToDelete != nil },
            set: { if !$0 { itemToDelete = nil } }
        )) {
            Button(L10n.t(.cancel), role: .cancel) { itemToDelete = nil }
            Button(L10n.t(.delete), role: .destructive) {
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
            title: selectedItem.kind == .reminder ? L10n.t(.paneReminder) : L10n.t(.paneSchedule),
            systemImage: selectedItem.kind == .reminder ? "checklist" : "calendar",
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

    private var modePicker: some View {
        Picker("", selection: $mode) {
            ForEach(Mode.allCases) { option in
                Text(modeTitle(option))
                    .tag(option)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .labelsHidden()
        .help(L10n.t(.switchViewMode))
    }

    private func modeTitle(_ mode: Mode) -> String {
        switch mode {
        case .all:     return L10n.t(.modeAll)
        case .week:    return L10n.t(.modeWeek)
        case .month:   return L10n.t(.modeMonth)
        case .commits: return L10n.t(.modeGit)
        }
    }

    private func sortName(_ option: SortOption) -> String {
        switch option {
        case .manual:       return L10n.pick("Manual", "手动")
        case .priorityDesc: return L10n.pick("Priority", "优先级")
        case .dateAsc:      return L10n.pick("Date", "日期")
        case .dateDesc:     return L10n.pick("Date (newest)", "日期（最新）")
        case .nameAsc:      return L10n.pick("Name", "名称")
        }
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
        .help(showTodayPanel.wrappedValue ? L10n.t(.hideTodayPanel) : L10n.t(.showTodayTimeline))
    }

    private var refreshButton: some View {
        Button {
            refreshTrigger += 1
            toast.show(L10n.t(.refreshed), type: .success, duration: 1.5)
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 11, weight: .medium))
        }
        .help(L10n.t(.refresh))
    }

    private var toolbarActions: some View {
        HStack(spacing: 3) {
            todayButton
            refreshButton
        }
    }

    private var actionCluster: some View {
        ItemActionCluster(itemFilter: $itemFilter, showCompleted: $showCompleted, animation: listAnimation) {
            beginCreate()
        } accessory: {
            sortPill
        }
    }

    private var sortPill: some View {
        Menu {
            ForEach(SortOption.allCases) { option in
                Button {
                    sortOption = option
                } label: {
                    HStack {
                        Image(systemName: option.systemImage)
                        Text(sortName(option))
                        if sortOption == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: sortOption.systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(sortOption == .manual ? .secondary : Color.accentColor)
                .frame(width: 26, height: 24)
                .background(sortOption == .manual ? Color.clear : Color.accentColor.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L10n.pick("Sort: \(sortOption.rawValue)", "排序：\(sortName(sortOption))"))
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

            if !tagFilter.isEmpty {
                ActiveTagFilterBar(tagFilter: $tagFilter)
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

            if itemFilter.isActive {
                FacetInfoBadge(
                    text: "\(visibleItems.count) shown",
                    systemImage: "line.3.horizontal.decrease.circle",
                    tint: .secondary,
                    fill: Color.accentColor.opacity(0.08)
                )
            }

            if hiddenReminderCount > 0 {
                FacetInfoBadge(
                    text: "\(hiddenReminderCount) hidden",
                    systemImage: "eye.slash",
                    tint: .secondary,
                    fill: Color.orange.opacity(0.08)
                )
            }

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

    private var allItemsList: some View {
        Group {
            if visibleItems.isEmpty && !(loading && items.isEmpty) {
                emptyAllItemsView
            } else {
                List {
                    itemKindSection(title: L10n.pick("Tasks", "任务"), systemImage: "checklist",
                                    count: taskItems.count, color: .green, items: taskItems)
                    itemKindSection(title: L10n.pick("Events", "事件"), systemImage: "calendar",
                                    count: scheduleItems.count, color: .blue, items: scheduleItems)
                    itemKindSection(title: L10n.pick("Literature", "文献"), systemImage: "books.vertical",
                                    count: literatureItems.count, color: .yellow, items: literatureItems)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .thinScrollIndicators()
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
        if hasActiveSearch { return L10n.pick("No results", "无结果") }
        return items.isEmpty ? L10n.pick("No items yet", "暂无条目")
                             : L10n.pick("Completed items hidden", "已隐藏完成的条目")
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
        if hasActiveSearch {
            return L10n.pick("No items match “\(searchText)”.", "没有匹配“\(searchText)”的条目。")
        }
        return items.isEmpty ? L10n.pick("No items yet.", "暂无条目。")
                             : L10n.pick("Completed items are hidden.", "已隐藏完成的条目。")
    }

    private var summaryCluster: some View {
        HStack(spacing: 6) {
            SummaryChip(value: openTaskCount, label: L10n.pick("Tasks", "任务"), systemImage: "circle")
            SummaryChip(value: eventCount, label: L10n.pick("Events", "事件"), systemImage: "calendar")
            SummaryChip(value: literatureCount, label: L10n.pick("Literature", "文献"), systemImage: "books.vertical")
            SummaryChip(value: completedReminderCount, label: L10n.pick("Done", "已完成"), systemImage: "checkmark.circle")
        }
    }

    private var openTaskCount: Int {
        itemCounts.openReminderCount
    }

    private var eventCount: Int {
        itemCounts.eventCount
    }

    private var literatureCount: Int {
        itemCounts.literatureCount
    }

    private var completedReminderCount: Int {
        itemCounts.completedReminderCount
    }

    private var hiddenReminderCount: Int {
        guard !showCompleted else { return 0 }
        return allScopedItems.filter { $0.kind == .reminder && $0.isCompleted }.count
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
            onEntered: { dragged, target in previewDropEntered(dragged: dragged, target: target) },
            onDrop: { finishDrag() }
        ))
        .opacity(draggedItem?.id == item.id ? 0.32 : 1.0)
    }

    // ── Drag-drop preview / commit ────────────────────────────────────────────

    /// Drop-enter handler used by every row's `ItemDropDelegate`.
    /// Same kind → live reorder (existing behaviour).
    /// Different kind → optimistic kind swap so the row slides into the other
    /// section during the drag, matching how WeekView previews cross-day moves.
    private func previewDropEntered(dragged: ProjectItem, target: ProjectItem) {
        if dragged.kind == target.kind {
            moveItem(from: dragged, to: target)
        } else if dragged.linkedPaperIDs.isEmpty {
            previewKindChange(dragged: dragged, target: target)
        }
    }

    private func previewKindChange(dragged: ProjectItem, target: ProjectItem) {
        guard let fromIndex = items.firstIndex(where: { $0.id == dragged.id }) else { return }
        let updated = dragged.replacingKind(target.kind)
        let targetIndex = items.firstIndex(where: { $0.id == target.id })
        withAnimation(FacetTheme.dragPreviewAnimation) {
            items.remove(at: fromIndex)
            if let targetIndex {
                let adjusted = fromIndex < targetIndex ? targetIndex - 1 : targetIndex
                items.insert(updated, at: min(max(adjusted, 0), items.count))
            } else {
                items.append(updated)
            }
            if draggedItem?.id == updated.id { draggedItem = updated }
            if selectedDetailItem?.id == updated.id { selectedDetailItem = updated }
        }
    }

    private func finishDrag() {
        guard let dragged = draggedItem else { return }
        let snapshot = dragSnapshot
        let original = snapshot?.first(where: { $0.id == dragged.id }) ?? dragged
        guard let current = items.first(where: { $0.id == dragged.id }) else {
            cancelDrag()
            return
        }
        if original.kind != current.kind {
            draggedItem = nil
            persistKindChange(original: original, current: current, snapshot: snapshot)
        } else {
            commitItemOrder()
            dragSnapshot = nil
            draggedItem = nil
        }
    }

    private func persistKindChange(original: ProjectItem, current: ProjectItem, snapshot: [ProjectItem]?) {
        guard original.linkedPaperIDs.isEmpty else {
            if let snapshot {
                withAnimation(listAnimation) { items = snapshot }
            }
            dragSnapshot = nil
            draggedItem = nil
            return
        }
        let metadata = original.facetItemMetadata()
        Task {
            let newId: String?
            if original.kind == .reminder {
                let calName = project.calendarName ?? ""
                newId = await ek.convertReminderToEvent(
                    reminderId: original.id,
                    project: project.prefix,
                    content: original.content,
                    tags: original.tags,
                    itemMetadata: metadata,
                    dueDate: original.date,
                    durationMinutes: settings.defaultEventDurationMinutes,
                    calendarName: calName.isEmpty ? settings.defaultCalendarName : calName,
                    enabledCalendars: settings.effectiveCalendarNames
                )
            } else {
                let listName = project.reminderListName ?? ""
                newId = await ek.convertEventToReminder(
                    eventId: original.id,
                    project: project.prefix,
                    content: original.content,
                    tags: original.tags,
                    itemMetadata: metadata,
                    priority: original.priority,
                    startDate: original.date,
                    hasTime: original.hasTime,
                    listName: listName.isEmpty ? settings.defaultReminderListName : listName,
                    enabledLists: settings.effectiveReminderListNames
                )
            }
            if let newId {
                commitItemOrder()
                dragSnapshot = nil
                refreshTrigger += 1
                await reload(selecting: newId)
            } else {
                if let snapshot {
                    withAnimation(listAnimation) { items = snapshot }
                }
                dragSnapshot = nil
                toast.show(L10n.pick("Could not convert item", "无法转换条目"), type: .error)
            }
        }
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
            toast.show(L10n.pick("Choose a reminder list first", "请先选择一个提醒事项列表"), type: .error)
            return
        }
        Task {
            let dueDate = initialDate.map { FacetDateDefaults.dayDefault(reference: $0) }
            guard let id = await ek.createReminder(
                project: project.prefix,
                content: L10n.pick("New Task", "新任务"),
                listName: listName,
                dueDate: dueDate,
                dueIncludesTime: false,
                enabledLists: settings.effectiveReminderListNames
            ) else {
                toast.show(L10n.pick("Could not create item", "无法创建条目"), type: .error)
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
