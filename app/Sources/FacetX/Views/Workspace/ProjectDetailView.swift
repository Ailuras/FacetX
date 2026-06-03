import AppKit
import FacetXCore
import SwiftUI

struct ProjectDetailView: View {
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var keyboard: KeyboardActionRouter
    let project: Project

    enum Mode: String, CaseIterable, Identifiable {
        case all = "All", week = "Week", month = "Month", commits = "Git"
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
    @State private var itemToDelete: ProjectItem? = nil

    private var listAnimation: Animation { FacetTheme.listSpring }
    private var detailPaneAnimation: Animation { .spring(response: 0.34, dampingFraction: 0.88) }

    private var visibleItems: [ProjectItem] {
        let base = showCompleted ? items : items.filter { !$0.isCompleted }
        return base.filter { $0.matches(searchQuery: searchText) }
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

    private var taskGroups: [ItemArrangement.ZoneGroup] {
        ItemArrangement.groupedByZone(taskItems)
    }

    private var scheduleGroups: [ItemArrangement.ZoneGroup] {
        ItemArrangement.groupedByZone(scheduleItems)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Group {
                    switch mode {
                    case .all: allItemsView
                    case .week: WeekView(project: project, searchText: searchText, showCompleted: showCompleted, selectedItem: $selectedDetailItem)
                    case .month: MonthView(project: project, searchText: searchText, showCompleted: showCompleted, selectedItem: $selectedDetailItem)
                    case .commits: CommitsView(project: project)
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
                ToolbarSearchField(text: $searchText, placeholder: "Search items…")
                    .frame(width: 220, height: 24)
            }
            ToolbarItem(placement: .automatic) {
                refreshButton
            }
        }
        .sheet(isPresented: $showCreate) {
            CreateItemView(project: project) { Task { await reload() } }
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
            }
        }
        .onReceive(keyboard.commandPublisher) { cmd in
            switch cmd {
            case .modeAll:     mode = .all
            case .modeWeek:    mode = .week
            case .modeMonth:   mode = .month
            case .modeGit:     mode = .commits
            case .newItem:     showCreate = true
            case .refresh:     Task { await reload() }
            case .toggleShowCompleted:
                withAnimation(listAnimation) { showCompleted.toggle() }
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
                withAnimation(detailPaneAnimation) { selectedDetailItem = nil }
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
        ItemDetailPane(item: selectedItem, project: project, onClose: {
            withAnimation(detailPaneAnimation) {
                selectedDetailItem = nil
            }
        }, onUpdate: {
            Task { await reload() }
        })
        .frame(width: 360)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(FacetTheme.hairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 8)
        .padding(.vertical, 10)
        .padding(.trailing, 10)
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        ))
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

    private var refreshButton: some View {
        Button {
            Task { await reload() }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 11, weight: .medium))
        }
        .help("Refresh")
    }

    private var actionCluster: some View {
        HStack(spacing: 2) {
            pillButton(systemName: showCompleted ? "checkmark.circle.fill" : "checkmark.circle",
                       help: showCompleted ? "Hide completed reminders" : "Show completed reminders",
                       active: showCompleted) {
                withAnimation(listAnimation) { showCompleted.toggle() }
            }
            pillButton(systemName: "plus", help: "Add an item to this project") {
                showCreate = true
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
    }

    private var allViewInfoBar: some View {
        HStack(spacing: 12) {
            summaryCluster

            Spacer()

            if hasActiveSearch {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("\(visibleItems.count) results")
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

            if !showCompleted && completedReminderCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("\(completedReminderCount) hidden")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.orange.opacity(0.08))
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
                itemKindSection(title: "Tasks", systemImage: "checklist",
                                count: taskItems.count, color: .green, groups: taskGroups)
                itemKindSection(title: "Schedule", systemImage: "calendar",
                                count: scheduleItems.count, color: .blue, groups: scheduleGroups)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .animation(listAnimation, value: visibleItems.map { "\($0.id)-\($0.isCompleted)" })
    }

    @ViewBuilder private func itemKindSection(title: String, systemImage: String,
                                              count: Int, color: Color,
                                              groups: [ItemArrangement.ZoneGroup]) -> some View {
        if !groups.isEmpty {
            itemKindHeader(title: title, systemImage: systemImage, count: count, color: color)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 14, leading: 14, bottom: 4, trailing: 14))

            ForEach(groups, id: \.zone) { group in
                zoneHeader(group.zone, count: group.items.count)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 18, bottom: 2, trailing: 14))

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

    private func zoneHeader(_ zone: String, count: Int? = nil) -> some View {
        HStack(spacing: 6) {
            Text(zone)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            if let count {
                Text("\(count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        items.filter { $0.kind == .reminder && !$0.isCompleted }.count
    }

    private var eventCount: Int {
        items.filter { $0.kind == .event }.count
    }

    private var completedReminderCount: Int {
        items.filter { $0.kind == .reminder && $0.isCompleted }.count
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
                            try? await Task.sleep(for: .milliseconds(80))
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
                    await ItemActionHelpers.toggleCompletion(item, completed: completed, ek: ek)
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
                Task { await ItemActionHelpers.deleteItem(item, ek: ek); await reload() }
            }
        }
        .itemSelectionGestures(
            item: item,
            selectedItem: $selectedDetailItem,
            onDoubleTap: { startInlineEdit(for: item) }
        )
        .onDrop(of: [.text], delegate: ItemDropDelegate(
            item: item,
            draggedItem: $draggedItem,
            onMove: { dragged, target in moveItem(from: dragged, to: target) },
            onDrop: { commitItemOrder(); dragSnapshot = nil }
        ))
        .opacity(draggedItem?.id == item.id ? 0.32 : 1.0)
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
                projectPrefix: project.prefix,
                ek: ek
            )
            inlineEditingID = nil
            await reload()
        }
    }

    private func cancelInlineEdit(for item: ProjectItem) {
        ItemEditHelpers.cancelTitleEdit(editingID: &inlineEditingID)
    }

    private func startInlineNotesEdit(for item: ProjectItem) {
        ItemEditHelpers.startNotesEdit(for: item, editingID: &inlineEditingNotesID, editingText: &inlineEditingNotesText)
    }

    private func commitInlineNotesEdit(for item: ProjectItem) {
        Task {
            _ = await ItemEditHelpers.commitNotesEdit(
                editingID: inlineEditingNotesID,
                editingText: inlineEditingNotesText,
                for: item,
                projectPrefix: project.prefix,
                ek: ek
            )
            inlineEditingNotesID = nil
            await reload()
        }
    }

    private func cancelInlineNotesEdit(for item: ProjectItem) {
        ItemEditHelpers.cancelNotesEdit(editingID: &inlineEditingNotesID)
    }

    private func reload() async {
        loading = items.isEmpty
        let fetched = await ek.items(forProject: project.prefix,
                                     enabledReminderLists: settings.effectiveReminderListNames,
                                     enabledCalendars: settings.effectiveCalendarNames)
        store.pruneItemOrder(projectID: project.id, keeping: Set(fetched.map(\.id)))
        let sortedItems = ItemArrangement.arranged(fetched, savedOrder: project.itemOrder)
        let selectedId = selectedDetailItem?.id
        let firstPopulation = items.isEmpty

        let apply = {
            items = sortedItems
            if let selectedId {
                selectedDetailItem = visibleItems.first { $0.id == selectedId }
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
