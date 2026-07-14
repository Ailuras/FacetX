import Foundation
import FacetXCore

/// A saved work. Owns calendar/reminder items by title prefix; the items
/// themselves live in EventKit, not here. This store holds only work-side
/// metadata EventKit cannot represent.
struct Work: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    /// The title prefix this work claims. Defaults to `name` but is editable
    /// so it need not collide with historical action-type prefixes.
    var prefix: String
    var tagline: String = ""
    /// Where new work reminders/events are saved by default.
    var reminderListName: String?
    var calendarName: String?
    var weekGoalCalendarName: String?
    var archived: Bool = false
    var weekGoals: [WeekGoal] = []
    var itemOrder: [String] = []
    var colorName: String?
    var iconName: String?
    /// Manual sort index for sidebar ordering (lower = higher).
    var sortOrder: Int = 0
    /// GitHub repository in "owner/repo" format (optional).
    var githubRepo: String?
    var githubLocalPath: String?

    init(name: String, prefix: String? = nil, tagline: String = "",
         reminderListName: String? = nil, calendarName: String? = nil,
         weekGoalCalendarName: String? = nil,
         colorName: String? = nil, iconName: String? = nil,
         githubRepo: String? = nil,
         githubLocalPath: String? = nil) {
        self.name = name
        self.prefix = prefix ?? name
        self.tagline = tagline
        self.reminderListName = reminderListName
        self.calendarName = calendarName
        self.weekGoalCalendarName = weekGoalCalendarName
        self.colorName = colorName
        self.iconName = iconName
        self.githubRepo = githubRepo
        self.githubLocalPath = githubLocalPath
    }
}

/// A per-week goal attached to a work. ISO week id like "2026-W22".
struct WeekGoal: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var weekId: String
    var title: String
    var body: String = ""
    /// The EventKit event identifier for the week-spanning goal event.
    var eventId: String? = nil
}

/// Persists saved works to a JSON file under Application Support.
/// Small dataset → a plain Codable store beats SwiftData here and keeps the
/// pure-SwiftPM (Command Line Tools) build working.
@MainActor
final class WorkStore: ObservableObject {
    @Published private(set) var works: [Work] = []
    @Published private(set) var tagsByWork: [Work.ID: [String: Int]] = [:]
    @Published private(set) var persistenceError: String?

    var discoveredTags: [String: Int] {
        var aggregate: [String: Int] = [:]
        for (_, counts) in tagsByWork {
            for (tag, count) in counts {
                aggregate[tag, default: 0] += count
            }
        }
        return aggregate
    }

    private let url: URL

    init(filename: String = "works.json") {
        self.url = AppSupport.directory().appendingPathComponent(filename)
        load()
    }

    var activeWorks: [Work] {
        works.enumerated()
            .filter { !$0.element.archived }
            .sorted {
                if $0.element.sortOrder != $1.element.sortOrder {
                    return $0.element.sortOrder < $1.element.sortOrder
                }
                return $0.offset < $1.offset
            }
            .map(\.element)
    }

    @discardableResult
    func createWork(name: String, prefix: String? = nil, tagline: String = "",
                       reminderListName: String? = nil, calendarName: String? = nil,
                       weekGoalCalendarName: String? = nil,
                       colorName: String? = nil, iconName: String? = nil,
                       githubRepo: String? = nil,
                       githubLocalPath: String? = nil) -> Work.ID {
        let maxOrder = works.map(\.sortOrder).max() ?? -1
        var work = Work(name: name, prefix: prefix, tagline: tagline,
                              reminderListName: reminderListName, calendarName: calendarName,
                              weekGoalCalendarName: weekGoalCalendarName,
                              colorName: colorName, iconName: iconName,
                              githubRepo: githubRepo,
                              githubLocalPath: githubLocalPath)
        work.sortOrder = maxOrder + 1
        works.append(work)
        save()
        return work.id
    }

    func update(_ work: Work) {
        guard let i = works.firstIndex(where: { $0.id == work.id }) else { return }
        works[i] = work
        save()
    }

    func archive(_ work: Work) {
        guard let i = works.firstIndex(where: { $0.id == work.id }) else { return }
        works[i].archived = true
        save()
    }

    func unarchive(_ work: Work) {
        guard let i = works.firstIndex(where: { $0.id == work.id }) else { return }
        works[i].archived = false
        save()
    }

    var archivedWorks: [Work] {
        works.filter { $0.archived }.sorted { $0.sortOrder < $1.sortOrder }
    }

    func delete(_ work: Work) {
        works.removeAll { $0.id == work.id }
        save()
    }

    // ── Work ordering ─────────────────────────────────────────────────────

    func reorderWorks(from source: IndexSet, to destination: Int) {
        var active = works.filter { !$0.archived }.sorted { $0.sortOrder < $1.sortOrder }
        active.move(fromOffsets: source, toOffset: destination)
        for (index, work) in active.enumerated() {
            if let i = works.firstIndex(where: { $0.id == work.id }) {
                works[i].sortOrder = index
            }
        }
        save()
    }

    // ── Week goals ────────────────────────────────────────────────────────────

    func weekGoal(workID: Work.ID, weekId: String) -> WeekGoal? {
        works.first { $0.id == workID }?
            .weekGoals.first { $0.weekId == weekId }
    }

    /// Create or update the goal for a work's week. Empty title removes it.
    /// `eventId` ties the goal to a week-spanning EventKit event.
    func setWeekGoal(workID: Work.ID, weekId: String, title: String, body: String, eventId: String? = nil) {
        guard let p = works.firstIndex(where: { $0.id == workID }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        if let g = works[p].weekGoals.firstIndex(where: { $0.weekId == weekId }) {
            if trimmed.isEmpty {
                works[p].weekGoals.remove(at: g)
            } else {
                works[p].weekGoals[g].title = trimmed
                works[p].weekGoals[g].body = body
                if let eventId {
                    works[p].weekGoals[g].eventId = eventId
                }
            }
        } else if !trimmed.isEmpty {
            var goal = WeekGoal(weekId: weekId, title: trimmed, body: body)
            goal.eventId = eventId
            works[p].weekGoals.append(goal)
        }
        save()
    }

    // ── Tag discovery ─────────────────────────────────────────────────────────

    /// Replace this work's tag counts with the tags found in the given items.
    /// Called from each work's reload — aggregated counts are recomputed lazily.
    func reportTags(workID: Work.ID, items: [WorkItem]) {
        var counts: [String: Int] = [:]
        for item in items {
            for tag in item.tags {
                counts[tag, default: 0] += 1
            }
        }
        if tagsByWork[workID] != counts {
            tagsByWork[workID] = counts
        }
    }

    // ── Item ordering ────────────────────────────────────────────────────────

    func setItemOrder(workID: Work.ID, orderedIDs: [String]) {
        guard let p = works.firstIndex(where: { $0.id == workID }) else { return }
        works[p].itemOrder = orderedIDs
        save()
    }

    func pruneItemOrder(workID: Work.ID, keeping validIDs: Set<String>) {
        guard let p = works.firstIndex(where: { $0.id == workID }) else { return }
        let order = works[p].itemOrder
        let pruned = order.filter { validIDs.contains($0) }
        guard pruned != order else { return }
        works[p].itemOrder = pruned
        save()
    }

    // ── Persistence ──────────────────────────────────────────────────────────

    private func load() {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            works = try JSONDecoder().decode([Work].self, from: data)
            persistenceError = nil
        } catch {
            persistenceError = "Could not read works.json: \(error.localizedDescription)"
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(works).write(to: url, options: .atomic)
            persistenceError = nil
        } catch {
            persistenceError = "Could not write works.json: \(error.localizedDescription)"
        }
    }
}
