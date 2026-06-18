import AppKit
import FacetXCore
import SwiftUI

struct ItemInlineEditState {
    var titleID: String?
    var titleText = ""
    var notesID: String?
    var notesText = ""

    mutating func startTitleEdit(for item: ProjectItem) {
        titleText = item.content
        titleID = item.id
    }

    mutating func cancelTitleEdit() {
        titleID = nil
    }

    mutating func cancelNotesEdit() {
        notesID = nil
    }
}

struct StandardItemRow: View {
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: ProjectStore
    @State private var noteStore = ItemStore.shared

    let item: ProjectItem
    let projectPrefix: String
    @Binding var selectedItem: ProjectItem?
    @Binding var inlineEdit: ItemInlineEditState
    var projectBadge: String?
    var showDragGrip = true
    var onDragStart: (() -> NSItemProvider)?
    var onReload: () async -> Void
    var onDeleteRequest: (ProjectItem) -> Void

    var body: some View {
        ItemRow(
            item: item,
            isSelected: item.id == selectedItem?.id,
            projectBadge: projectBadge,
            showDragGrip: showDragGrip,
            onDragStart: onDragStart,
            onToggle: { completed in
                Task {
                    await ItemActionHelpers.toggleCompletion(item, completed: completed, ek: ek)
                    await onReload()
                }
            },
            onEdit: select,
            inlineEditingText: $inlineEdit.titleText,
            isInlineEditing: item.id == inlineEdit.titleID,
            onInlineCommit: commitTitleEdit,
            onInlineCancel: {
                inlineEdit.cancelTitleEdit()
            },
            inlineEditingNotesText: $inlineEdit.notesText,
            isInlineEditingNotes: item.id == inlineEdit.notesID,
            onInlineNotesCommit: commitNotesEdit,
            onInlineNotesCancel: {
                inlineEdit.cancelNotesEdit()
            },
            onStartNotesEdit: {
                startNotesEdit()
            }
        )
        .swipeActions(edge: .leading, allowsFullSwipe: !leadingAction.isDestructive) {
            swipeButton(leadingAction)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: !trailingAction.isDestructive) {
            swipeButton(trailingAction)
        }
        .contextMenu {
            Button(L10n.pick("Edit...", "编辑…")) {
                select()
            }
            Divider()
            Menu(L10n.pick("Set Date", "设置日期")) {
                Button(L10n.pick("Today", "今天")) { reschedule(to: today) }
                Button(L10n.pick("Tomorrow", "明天")) { reschedule(to: tomorrow) }
                Button(L10n.pick("This Weekend", "本周末")) { reschedule(to: thisWeekend) }
                Button(L10n.pick("Next Week", "下周")) { reschedule(to: nextWeek) }
                if item.kind == .reminder, item.date != nil {
                    Divider()
                    Button(L10n.pick("Clear Date", "清除日期")) { clearDate() }
                }
            }
            if item.kind == .reminder {
                Menu(L10n.pick("Priority", "优先级")) {
                    Button(L10n.pick("None", "无")) { setPriority(0) }
                    Button(L10n.pick("Low", "低")) { setPriority(9) }
                    Button(L10n.pick("Medium", "中")) { setPriority(5) }
                    Button(L10n.pick("High", "高")) { setPriority(1) }
                }
            }
            Button(L10n.pick("Copy Title", "复制标题")) { copyTitle() }
            if item.linkedPaperIDs.isEmpty {
                Divider()
                Button(item.kind == .reminder ? L10n.pick("Convert to Event", "转为事件")
                                              : L10n.pick("Convert to Task", "转为任务")) {
                    convertItemType()
                }
            }
            Divider()
            Button(L10n.pick("Delete", "删除"), role: .destructive) {
                onDeleteRequest(item)
            }
        }
        .itemSelectionGestures(
            item: item,
            selectedItem: $selectedItem
        )
    }

    // MARK: - Swipe

    private var leadingAction: SwipeAction {
        SwipeAction(rawValue: settings.leadingSwipeAction) ?? .none
    }

    private var trailingAction: SwipeAction {
        SwipeAction(rawValue: settings.trailingSwipeAction) ?? .none
    }

    /// Destructive actions never full-swipe (they need a deliberate tap). The
    /// system tint is cleared so only our own pill shows — icon + title sit
    /// together inside a short rounded chip that matches the app's card radius,
    /// instead of the tall full-height capsule the native style draws.
    @ViewBuilder
    private func swipeButton(_ action: SwipeAction) -> some View {
        if action.isApplicable(to: item) {
            Button {
                perform(action)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: action.systemImage)
                        .font(.system(size: 12, weight: .semibold))
                    Text(action.title)
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                        .fill(action.tint)
                )
            }
            .tint(.clear)
        }
    }

    private func perform(_ action: SwipeAction) {
        switch action {
        case .none: break
        case .today: reschedule(to: today)
        case .tomorrow: reschedule(to: tomorrow)
        case .complete: toggleComplete()
        case .delete: onDeleteRequest(item)
        case .convert: convertItemType()
        }
    }

    // MARK: - Quick actions (shared by swipe + context menu)

    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    private var tomorrow: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
    }
    private var nextWeek: Date {
        Calendar.current.date(byAdding: .day, value: 7, to: today) ?? today
    }
    /// The nearest upcoming Saturday (start of day).
    private var thisWeekend: Date {
        let cal = Calendar.current
        let saturday = cal.nextDate(after: Date(),
                                    matching: DateComponents(weekday: 7),
                                    matchingPolicy: .nextTime) ?? Date()
        return cal.startOfDay(for: saturday)
    }

    private func toggleComplete() {
        Task {
            await ItemActionHelpers.toggleCompletion(item, completed: !item.isCompleted, ek: ek)
            await onReload()
        }
    }

    private func reschedule(to day: Date) {
        Task {
            await ItemActionHelpers.reschedule(item, toDay: day, ek: ek)
            await onReload()
        }
    }

    private func clearDate() {
        Task {
            await ItemActionHelpers.clearDate(item, ek: ek)
            await onReload()
        }
    }

    private func convertItemType() {
        let proj = store.activeProjects.first { $0.prefix == projectPrefix }
        let metadata = item.facetItemMetadata()
        Task {
            let newId: String?
            if item.kind == .reminder {
                let calName = proj?.calendarName ?? ""
                newId = await ek.convertReminderToEvent(
                    reminderId: item.id,
                    project: item.projectPrefix,
                    content: item.content,
                    tags: item.tags,
                    itemMetadata: metadata,
                    dueDate: item.date,
                    durationMinutes: settings.defaultEventDurationMinutes,
                    calendarName: calName.isEmpty ? settings.defaultCalendarName : calName
                )
            } else {
                let listName = proj?.reminderListName ?? ""
                newId = await ek.convertEventToReminder(
                    eventId: item.id,
                    project: item.projectPrefix,
                    content: item.content,
                    tags: item.tags,
                    itemMetadata: metadata,
                    priority: item.priority,
                    startDate: item.date,
                    hasTime: item.hasTime,
                    listName: listName.isEmpty ? settings.defaultReminderListName : listName
                )
            }
            if newId != nil { await onReload() }
        }
    }

    private func setPriority(_ priority: Int) {
        Task {
            await ItemActionHelpers.setPriority(item, priority: priority, ek: ek)
            await onReload()
        }
    }

    private func copyTitle() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.content, forType: .string)
    }

    private func select() {
        ItemSelectionHelpers.toggleSelection(item, selectedItem: &selectedItem)
    }

    private func commitTitleEdit() {
        Task {
            _ = await ItemEditHelpers.commitTitleEdit(
                editingID: inlineEdit.titleID,
                editingText: inlineEdit.titleText,
                for: item,
                projectPrefix: projectPrefix,
                ek: ek
            )
            await MainActor.run {
                inlineEdit.titleID = nil
            }
            await onReload()
        }
    }

    private func commitNotesEdit() {
        Task {
            guard inlineEdit.notesID == item.id else { return }
            let facetID = item.facetID ?? UUID().uuidString
            noteStore.save(id: facetID, body: inlineEdit.notesText.trimmingCharacters(in: .whitespacesAndNewlines))
            if item.facetID == nil {
                _ = await ek.rewriteItemMetadata(id: item.id, metadata: FacetItemMetadata(itemID: facetID))
            }
            await MainActor.run {
                inlineEdit.notesID = nil
            }
            await onReload()
        }
    }

    private func startNotesEdit() {
        if let facetID = item.facetID {
            inlineEdit.notesText = noteStore.body(for: facetID)
        } else {
            inlineEdit.notesText = ""
        }
        inlineEdit.notesID = item.id
    }
}
