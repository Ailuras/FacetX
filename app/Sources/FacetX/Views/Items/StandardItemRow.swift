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
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if item.kind == .reminder {
                Button {
                    toggleComplete()
                } label: {
                    Label(item.isCompleted ? "Uncomplete" : "Complete",
                          systemImage: item.isCompleted ? "arrow.uturn.left" : "checkmark.circle")
                }
                .tint(.green)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                reschedule(to: today)
            } label: {
                Label("Today", systemImage: "calendar")
            }
            .tint(.blue)
            Button {
                reschedule(to: tomorrow)
            } label: {
                Label("Tomorrow", systemImage: "arrow.right")
            }
            .tint(.orange)
        }
        .contextMenu {
            Button("Edit...") {
                select()
            }
            if item.kind == .reminder {
                Button(item.isCompleted ? "Mark Incomplete" : "Mark Complete") {
                    toggleComplete()
                }
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
            Button("Delete", role: .destructive) {
                onDeleteRequest(item)
            }
        }
        .itemSelectionGestures(
            item: item,
            selectedItem: $selectedItem
        )
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
