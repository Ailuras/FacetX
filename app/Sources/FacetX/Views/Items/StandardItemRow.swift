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
        .contextMenu {
            Button("Edit...") {
                select()
            }
            Button("Delete", role: .destructive) {
                onDeleteRequest(item)
            }
        }
        .itemSelectionGestures(
            item: item,
            selectedItem: $selectedItem,
            onDoubleTap: {
                inlineEdit.startTitleEdit(for: item)
            }
        )
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
