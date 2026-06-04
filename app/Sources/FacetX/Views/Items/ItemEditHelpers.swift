import AppKit
import FacetXCore
import SwiftUI

// MARK: - Inline Editing Helpers

/// Shared helper methods for inline title/notes editing to avoid duplicating
/// the same logic across ContentView, TodayView, WeekView, etc.
enum ItemEditHelpers {

    static func startTitleEdit(for item: ProjectItem, editingID: inout String?, editingText: inout String) {
        editingText = item.content
        editingID = item.id
    }

    static func cancelTitleEdit(editingID: inout String?) {
        editingID = nil
    }

    static func startNotesEdit(for item: ProjectItem, editingID: inout String?, editingText: inout String) {
        editingText = item.notes ?? ""
        editingID = item.id
    }

    static func cancelNotesEdit(editingID: inout String?) {
        editingID = nil
    }

    /// Commit a title edit. Returns `true` if a mutation (or deletion) occurred.
    @discardableResult
    static func commitTitleEdit(
        editingID: String?,
        editingText: String,
        for item: ProjectItem,
        projectPrefix: String,
        ek: EventKitService
    ) async -> Bool {
        guard editingID == item.id else { return false }
        let newContent = editingText.trimmingCharacters(in: .whitespaces)

        if newContent.isEmpty {
            _ = await ek.deleteItem(id: item.id)
            return true
        } else if newContent != item.content {
            _ = await ek.updateItem(
                id: item.id,
                project: projectPrefix,
                content: newContent,
                date: item.date,
                useDate: item.kind == .event || item.date != nil,
                containerName: item.containerName,
                notes: item.notes,
                tags: item.tags,
                priority: item.priority,
                isAllDay: item.kind == .event ? item.isAllDay : nil,
                endDate: item.kind == .event ? item.endDate : nil
            )
            return true
        }
        return false
    }

    /// Commit a notes edit. Returns `true` if a mutation occurred.
    @discardableResult
    static func commitNotesEdit(
        editingID: String?,
        editingText: String,
        for item: ProjectItem,
        projectPrefix: String,
        ek: EventKitService
    ) async -> Bool {
        guard editingID == item.id else { return false }
        let newNotes = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        let notesParam = newNotes.isEmpty ? nil : newNotes

        if notesParam != item.notes {
            _ = await ek.updateItem(
                id: item.id,
                project: projectPrefix,
                content: item.content,
                date: item.date,
                useDate: item.kind == .event || item.date != nil,
                containerName: item.containerName,
                notes: notesParam,
                tags: item.tags,
                priority: item.priority,
                isAllDay: item.kind == .event ? item.isAllDay : nil,
                endDate: item.kind == .event ? item.endDate : nil
            )
            return true
        }
        return false
    }
}

// MARK: - Selection Helpers

enum ItemSelectionHelpers {
    static func toggleSelection(_ item: ProjectItem, selectedItem: inout ProjectItem?) {
        withAnimation(.easeOut(duration: 0.15)) {
            selectedItem = (selectedItem?.id == item.id) ? nil : item
        }
    }
}

enum ItemDragHelpers {
    static func startDrag(
        item: ProjectItem,
        items: [ProjectItem],
        draggedItem: inout ProjectItem?,
        dragSnapshot: inout [ProjectItem]?,
        cancelDrag: @escaping @MainActor () -> Void
    ) -> NSItemProvider {
        dragSnapshot = items
        draggedItem = item

        let timer = Timer(timeInterval: 0.05, repeats: true) { timer in
            let pressedButtons = NSEvent.pressedMouseButtons
            let isLeftPressed = (pressedButtons & (1 << 0)) != 0
            if !isLeftPressed {
                timer.invalidate()
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(80))
                    cancelDrag()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)

        return NSItemProvider(object: item.id as NSString)
    }
}

// MARK: - Row Modifiers

extension View {
    /// Attaches the standard tap-to-toggle and double-tap-to-edit gestures
    /// used by the All / Week / Month item rows.
    func itemSelectionGestures(
        item: ProjectItem,
        selectedItem: Binding<ProjectItem?>,
        onDoubleTap: @escaping () -> Void
    ) -> some View {
        self
            .onTapGesture(count: 2, perform: onDoubleTap)
            .onTapGesture {
                ItemSelectionHelpers.toggleSelection(item, selectedItem: &selectedItem.wrappedValue)
            }
    }
}

// MARK: - Action Helpers

enum ItemActionHelpers {
    static func toggleCompletion(_ item: ProjectItem, completed: Bool, ek: EventKitService) async {
        await ek.setReminderCompleted(id: item.id, completed: completed)
    }

    static func deleteItem(_ item: ProjectItem, ek: EventKitService) async {
        _ = await ek.deleteItem(id: item.id)
    }
}
