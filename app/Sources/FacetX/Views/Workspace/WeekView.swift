import FacetXCore
import SwiftUI

struct WeekView: View {
    @EnvironmentObject var ek: EventKitService
    @EnvironmentObject var store: ProjectStore
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var keyboard: KeyboardActionRouter

    let project: Project
    let searchText: String
    let showCompleted: Bool
    @Binding var selectedItem: ProjectItem?
    @Binding var selectedTag: String?
    let refreshTrigger: Int
    let onCreateItem: (Date?) -> Void

    @State var week = ISOWeek.containing(Date())
    @State var allItems: [ProjectItem] = []
    @State var loading = false
    @State var editingGoal = false
    @State var goalTitle = ""
    @State var goalBody = ""
    @State var savingGoal = false
    @State var goalError: String?
    @State var inlineEdit = ItemInlineEditState()
    @State var itemToDelete: ProjectItem?
    @State var draggedItem: ProjectItem?
    @State var dragSnapshot: [ProjectItem]?
    @State var dropTargetDate: Date?

    var listAnimation: Animation { FacetTheme.listSpring }

    var weekItems: [ProjectItem] {
        var weekItems = allItems.filter { item in
            guard let date = item.date else { return false }
            return week.contains(date)
        }
        if let tag = selectedTag {
            weekItems = ItemQuery.filteredByTag(weekItems, tag: tag)
        }
        return ItemQuery.searched(
            ItemQuery.completedVisibility(weekItems, showCompleted: showCompleted),
            query: searchText
        )
    }

    var nonGoalItems: [ProjectItem] { weekItems }

    var hasActiveSearch: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var goal: WeekGoal? {
        store.weekGoal(projectID: project.id, weekId: week.id)
    }

    var reloadKey: String {
        "\(project.id.uuidString)-\(week.id)"
    }

    var dayGroups: [DayGroup] {
        let cal = Calendar(identifier: .iso8601)
        var groups: [DayGroup] = []

        for offset in 0..<7 {
            guard let date = cal.date(byAdding: .day, value: offset, to: week.startDate) else { continue }
            let dayItems = nonGoalItems.filter { item in
                guard let d = item.date else { return false }
                return cal.isDate(d, inSameDayAs: date)
            }

            let wd = DateFormatter()
            wd.dateFormat = "EEE"
            let weekdayLabel = wd.string(from: date)

            let df = DateFormatter()
            df.dateFormat = "MMM d"
            let dateLabel = df.string(from: date)

            groups.append(DayGroup(
                date: date,
                label: "\(weekdayLabel), \(dateLabel)",
                weekdayLabel: weekdayLabel,
                items: dayItems,
                isToday: cal.isDateInToday(date)
            ))
        }
        return groups
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            weekNav
            VStack(alignment: .leading, spacing: 14) {
                goalSection
                itemsSection
                Spacer()
            }
            .padding(16)
        }
        .background(FacetTheme.canvas)
        .task(id: reloadKey) { await reload() }
        .onChange(of: ek.changeToken) { Task { await reload() } }
        .onChange(of: settings.changeToken) { Task { await reload() } }
        .onChange(of: refreshTrigger) { Task { await reload() } }
        .onReceive(keyboard.commandPublisher) { cmd in
            switch cmd {
            case .editSelectedItemTitle:
                guard let item = selectedItem else { return }
                inlineEdit.startTitleEdit(for: item)
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
}
