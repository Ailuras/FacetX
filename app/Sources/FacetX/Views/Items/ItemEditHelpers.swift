import AppKit
import FacetXCore
import SwiftUI

// MARK: - Inline Editing Helpers

/// Shared helper methods for inline title/notes editing to avoid duplicating
/// the same logic across ContentView, TodayView, WeekView, etc.
enum ItemEditHelpers {

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
                dateIncludesTime: item.hasTime,
                containerName: item.containerName,
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
    /// Attaches the standard immediate tap-to-toggle gesture used by item rows.
    func itemSelectionGestures(
        item: ProjectItem,
        selectedItem: Binding<ProjectItem?>
    ) -> some View {
        self
            .onTapGesture {
                ItemSelectionHelpers.toggleSelection(item, selectedItem: &selectedItem.wrappedValue)
            }
    }
}

// MARK: - Swipe Actions

/// A quick action bound to a left/right swipe on an item row. Persisted by
/// raw value in `AppSettings` and rendered by `StandardItemRow`.
enum SwipeAction: String, CaseIterable, Identifiable {
    case none
    case today
    case tomorrow
    case complete
    case delete
    case convert

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "None"
        case .today: return "Today"
        case .tomorrow: return "Tomorrow"
        case .complete: return "Complete"
        case .delete: return "Delete"
        case .convert: return "Convert"
        }
    }

    var systemImage: String {
        switch self {
        case .none: return "minus"
        case .today: return "calendar"
        case .tomorrow: return "sunrise"
        case .complete: return "checkmark.circle"
        case .delete: return "trash"
        case .convert: return "arrow.2.squarepath"
        }
    }

    var tint: Color {
        switch self {
        case .none: return .gray
        case .today: return .blue
        case .tomorrow: return .orange
        case .complete: return .green
        case .delete: return .red
        case .convert: return .purple
        }
    }

    var isDestructive: Bool { self == .delete }

    /// `none` shows nothing; conversion is limited to plain reminders/events.
    /// Completion now applies to every kind (events/notes store it locally).
    func isApplicable(to item: ProjectItem) -> Bool {
        switch self {
        case .none: return false
        case .convert: return item.linkedPaperIDs.isEmpty && !item.isNote
        default: return true
        }
    }
}

// MARK: - Action Helpers

enum ItemActionHelpers {
    static func toggleCompletion(_ item: ProjectItem, completed: Bool, ek: EventKitService) async {
        // Reminders (tasks & project papers) sync completion through EventKit;
        // events & notes have no native completion, so it's kept in the local store.
        if item.kind == .reminder {
            await ek.setReminderCompleted(id: item.id, completed: completed)
        } else if let facetID = item.facetID {
            await MainActor.run { ItemStore.shared.setCompleted(completed, for: facetID) }
        }
    }

    @MainActor
    static func togglePin(_ item: ProjectItem, pinned: Bool) {
        guard let facetID = item.facetID else { return }
        ItemStore.shared.setPinned(pinned, for: facetID)
    }

    static func deleteItem(_ item: ProjectItem, ek: EventKitService) async {
        _ = await ek.deleteItem(id: item.id)
    }

    // MARK: Rescheduling

    /// Start date for `item` moved onto `day`, preserving the original
    /// time-of-day for timed items and snapping to the day start otherwise.
    /// Mirrors WeekView's drag-move math so swipe / context-menu reschedules
    /// behave identically to dragging an item across days.
    static func startDate(for item: ProjectItem, toDay day: Date,
                          calendar: Calendar = .current) -> Date {
        guard let oldDate = item.date else { return calendar.startOfDay(for: day) }
        if (item.kind == .event && !item.isAllDay) || item.hasTime {
            let hour = calendar.component(.hour, from: oldDate)
            let minute = calendar.component(.minute, from: oldDate)
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        return calendar.startOfDay(for: day)
    }

    /// End date for an event whose start moved to `newStart`, keeping the
    /// original duration (or one day for all-day events). `nil` for reminders.
    static func endDate(for item: ProjectItem, newStart: Date,
                        calendar: Calendar = .current) -> Date? {
        guard item.kind == .event else { return nil }
        if item.isAllDay {
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: newStart))
        }
        guard let oldStart = item.date, let oldEnd = item.endDate else { return nil }
        let duration = oldEnd.timeIntervalSince(oldStart)
        return newStart.addingTimeInterval(duration > 0 ? duration : 3600)
    }

    /// Move `item` to `day`, preserving time-of-day and (for events) duration.
    static func reschedule(_ item: ProjectItem, toDay day: Date, ek: EventKitService) async {
        let newStart = startDate(for: item, toDay: day)
        _ = await ek.updateItem(
            id: item.id,
            project: item.projectPrefix,
            content: item.content,
            date: newStart,
            useDate: true,
            dateIncludesTime: item.hasTime,
            containerName: item.containerName,
            tags: item.tags,
            priority: item.priority,
            url: item.url,
            updateURL: false,
            isAllDay: item.kind == .event ? item.isAllDay : nil,
            endDate: endDate(for: item, newStart: newStart)
        )
    }

    /// Clear an item's date (reminders only; events always carry a date).
    static func clearDate(_ item: ProjectItem, ek: EventKitService) async {
        _ = await ek.updateItem(
            id: item.id,
            project: item.projectPrefix,
            content: item.content,
            date: nil,
            useDate: false,
            dateIncludesTime: false,
            containerName: item.containerName,
            tags: item.tags,
            priority: item.priority,
            url: item.url,
            updateURL: false,
            isAllDay: nil,
            endDate: nil
        )
    }

    /// Update a reminder's priority, leaving everything else untouched.
    static func setPriority(_ item: ProjectItem, priority: Int, ek: EventKitService) async {
        _ = await ek.updateItem(
            id: item.id,
            project: item.projectPrefix,
            content: item.content,
            date: item.date,
            useDate: item.kind == .event || item.date != nil,
            dateIncludesTime: item.hasTime,
            containerName: item.containerName,
            tags: item.tags,
            priority: priority,
            url: item.url,
            updateURL: false,
            isAllDay: item.kind == .event ? item.isAllDay : nil,
            endDate: item.kind == .event ? item.endDate : nil
        )
    }
}
