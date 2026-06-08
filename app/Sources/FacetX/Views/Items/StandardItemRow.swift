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

    mutating func startNotesEdit(for item: ProjectItem) {
        notesText = item.notes ?? ""
        notesID = item.id
    }

    mutating func cancelNotesEdit() {
        notesID = nil
    }
}

struct StandardItemRow: View {
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: ProjectStore

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
                inlineEdit.startNotesEdit(for: item)
            }
        )
        .swipeActions(edge: .leading, allowsFullSwipe: !leadingAction.isDestructive) {
            swipeButton(leadingAction)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: !trailingAction.isDestructive) {
            swipeButton(trailingAction)
        }
        .contextMenu {
            Button("Edit...") {
                select()
            }
            Divider()
            Menu("Set Date") {
                Button("Today") { reschedule(to: today) }
                Button("Tomorrow") { reschedule(to: tomorrow) }
                Button("This Weekend") { reschedule(to: thisWeekend) }
                Button("Next Week") { reschedule(to: nextWeek) }
                if item.kind == .reminder, item.date != nil {
                    Divider()
                    Button("Clear Date") { clearDate() }
                }
            }
            if item.kind == .reminder {
                Menu("Priority") {
                    Button("None") { setPriority(0) }
                    Button("Low") { setPriority(9) }
                    Button("Medium") { setPriority(5) }
                    Button("High") { setPriority(1) }
                }
            }
            Button("Copy Title") { copyTitle() }
            Divider()
            Button(item.kind == .reminder ? "Convert to Schedule" : "Convert to Reminder") {
                convertItemType()
            }
            Divider()
            Button("Delete", role: .destructive) {
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

    /// Destructive actions never full-swipe (they need a deliberate tap), and
    /// every action shows its icon + title so the revealed button reads the
    /// same way as the rest of the app's labelled controls.
    @ViewBuilder
    private func swipeButton(_ action: SwipeAction) -> some View {
        if action.isApplicable(to: item) {
            Button(role: action.isDestructive ? .destructive : nil) {
                perform(action)
            } label: {
                Label(action.title, systemImage: action.systemImage)
            }
            .tint(action.tint)
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
        Task {
            let newId: String?
            if item.kind == .reminder {
                let calName = proj?.calendarName ?? ""
                newId = await ek.convertReminderToEvent(
                    reminderId: item.id,
                    project: item.projectPrefix,
                    content: item.content,
                    notes: item.notes,
                    tags: item.tags,
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
                    notes: item.notes,
                    tags: item.tags,
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
            _ = await ItemEditHelpers.commitNotesEdit(
                editingID: inlineEdit.notesID,
                editingText: inlineEdit.notesText,
                for: item,
                projectPrefix: projectPrefix,
                ek: ek
            )
            await MainActor.run {
                inlineEdit.notesID = nil
            }
            await onReload()
        }
    }
}
