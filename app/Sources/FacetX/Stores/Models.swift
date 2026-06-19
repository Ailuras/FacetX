import Foundation
import FacetXCore

/// A saved project. Owns calendar/reminder items by title prefix; the items
/// themselves live in EventKit, not here. This store holds only project-side
/// metadata EventKit cannot represent.
struct Project: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    /// The title prefix this project claims. Defaults to `name` but is editable
    /// so it need not collide with historical action-type prefixes.
    var prefix: String
    var tagline: String = ""
    /// Where new project reminders/events are saved by default.
    var reminderListName: String?
    var calendarName: String?
    var weekGoalCalendarName: String?
    var literatureListName: String?
    /// Absolute path to the project's local data folder (markdown notes and
    /// future file-backed content live here). The app is not sandboxed, so the
    /// plain path is stored directly.
    var dataDirectory: String?
    var archived: Bool = false
    var weekGoals: [WeekGoal] = []
    var itemOrder: [String] = []
    var colorName: String?
    var iconName: String?
    /// Manual sort index for sidebar ordering (lower = higher).
    var sortOrder: Int = 0
    /// GitHub repository in "owner/repo" format (optional).
    var githubRepo: String?

    init(name: String, prefix: String? = nil, tagline: String = "",
         reminderListName: String? = nil, calendarName: String? = nil,
         weekGoalCalendarName: String? = nil, literatureListName: String? = nil,
         dataDirectory: String? = nil,
         colorName: String? = nil, iconName: String? = nil,
         githubRepo: String? = nil) {
        self.name = name
        self.prefix = prefix ?? name
        self.tagline = tagline
        self.reminderListName = reminderListName
        self.calendarName = calendarName
        self.weekGoalCalendarName = weekGoalCalendarName
        self.literatureListName = literatureListName
        self.dataDirectory = dataDirectory
        self.colorName = colorName
        self.iconName = iconName
        self.githubRepo = githubRepo
    }

    /// The folder notes are read/written from: the user-chosen `dataDirectory`
    /// when set, otherwise a per-project default under Application Support so
    /// notes work even before a custom location is picked.
    var effectiveDataDirectory: String {
        if let dataDirectory, !dataDirectory.isEmpty { return dataDirectory }
        let safePrefix = prefix.replacingOccurrences(of: "/", with: "-")
        return AppSupport.directory()
            .appendingPathComponent("ProjectData", isDirectory: true)
            .appendingPathComponent(safePrefix.isEmpty ? id.uuidString : safePrefix, isDirectory: true)
            .path
    }
}

/// A per-week goal attached to a project. ISO week id like "2026-W22".
struct WeekGoal: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var weekId: String
    var title: String
    var body: String = ""
    /// The EventKit event identifier for the week-spanning goal event.
    var eventId: String? = nil
}

/// Persists saved projects to a JSON file under Application Support.
/// Small dataset → a plain Codable store beats SwiftData here and keeps the
/// pure-SwiftPM (Command Line Tools) build working.
@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [Project] = []
    @Published private(set) var tagsByProject: [Project.ID: [String: Int]] = [:]
    @Published private(set) var persistenceError: String?

    var discoveredTags: [String: Int] {
        var aggregate: [String: Int] = [:]
        for (_, counts) in tagsByProject {
            for (tag, count) in counts {
                aggregate[tag, default: 0] += count
            }
        }
        return aggregate
    }

    private let url: URL

    init(filename: String = "projects.json") {
        self.url = AppSupport.directory().appendingPathComponent(filename)
        load()
    }

    var activeProjects: [Project] {
        projects.enumerated()
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
    func createProject(name: String, prefix: String? = nil, tagline: String = "",
                       reminderListName: String? = nil, calendarName: String? = nil,
                       weekGoalCalendarName: String? = nil, literatureListName: String? = nil,
                       dataDirectory: String? = nil,
                       colorName: String? = nil, iconName: String? = nil,
                       githubRepo: String? = nil) -> Project.ID {
        let maxOrder = projects.map(\.sortOrder).max() ?? -1
        var project = Project(name: name, prefix: prefix, tagline: tagline,
                              reminderListName: reminderListName, calendarName: calendarName,
                              weekGoalCalendarName: weekGoalCalendarName, literatureListName: literatureListName,
                              dataDirectory: dataDirectory,
                              colorName: colorName, iconName: iconName,
                              githubRepo: githubRepo)
        project.sortOrder = maxOrder + 1
        projects.append(project)
        save()
        return project.id
    }

    func update(_ project: Project) {
        guard let i = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[i] = project
        save()
    }

    func archive(_ project: Project) {
        guard let i = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[i].archived = true
        save()
    }

    func unarchive(_ project: Project) {
        guard let i = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[i].archived = false
        save()
    }

    var archivedProjects: [Project] {
        projects.filter { $0.archived }.sorted { $0.sortOrder < $1.sortOrder }
    }

    func delete(_ project: Project) {
        projects.removeAll { $0.id == project.id }
        save()
    }

    // ── Project ordering ─────────────────────────────────────────────────────

    func reorderProjects(from source: IndexSet, to destination: Int) {
        var active = projects.filter { !$0.archived }.sorted { $0.sortOrder < $1.sortOrder }
        active.move(fromOffsets: source, toOffset: destination)
        for (index, project) in active.enumerated() {
            if let i = projects.firstIndex(where: { $0.id == project.id }) {
                projects[i].sortOrder = index
            }
        }
        save()
    }

    // ── Week goals ────────────────────────────────────────────────────────────

    func weekGoal(projectID: Project.ID, weekId: String) -> WeekGoal? {
        projects.first { $0.id == projectID }?
            .weekGoals.first { $0.weekId == weekId }
    }

    /// Create or update the goal for a project's week. Empty title removes it.
    /// `eventId` ties the goal to a week-spanning EventKit event.
    func setWeekGoal(projectID: Project.ID, weekId: String, title: String, body: String, eventId: String? = nil) {
        guard let p = projects.firstIndex(where: { $0.id == projectID }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        if let g = projects[p].weekGoals.firstIndex(where: { $0.weekId == weekId }) {
            if trimmed.isEmpty {
                projects[p].weekGoals.remove(at: g)
            } else {
                projects[p].weekGoals[g].title = trimmed
                projects[p].weekGoals[g].body = body
                if let eventId {
                    projects[p].weekGoals[g].eventId = eventId
                }
            }
        } else if !trimmed.isEmpty {
            var goal = WeekGoal(weekId: weekId, title: trimmed, body: body)
            goal.eventId = eventId
            projects[p].weekGoals.append(goal)
        }
        save()
    }

    // ── Tag discovery ─────────────────────────────────────────────────────────

    /// Replace this project's tag counts with the tags found in the given items.
    /// Called from each project's reload — aggregated counts are recomputed lazily.
    func reportTags(projectID: Project.ID, items: [ProjectItem]) {
        var counts: [String: Int] = [:]
        for item in items {
            for tag in item.tags {
                counts[tag, default: 0] += 1
            }
        }
        if tagsByProject[projectID] != counts {
            tagsByProject[projectID] = counts
        }
    }

    // ── Item ordering ────────────────────────────────────────────────────────

    func setItemOrder(projectID: Project.ID, orderedIDs: [String]) {
        guard let p = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[p].itemOrder = orderedIDs
        save()
    }

    func pruneItemOrder(projectID: Project.ID, keeping validIDs: Set<String>) {
        guard let p = projects.firstIndex(where: { $0.id == projectID }) else { return }
        let order = projects[p].itemOrder
        let pruned = order.filter { validIDs.contains($0) }
        guard pruned != order else { return }
        projects[p].itemOrder = pruned
        save()
    }

    // ── Persistence ──────────────────────────────────────────────────────────

    private func load() {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            projects = try JSONDecoder().decode([Project].self, from: data)
            persistenceError = nil
        } catch {
            persistenceError = "Could not read projects.json: \(error.localizedDescription)"
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(projects).write(to: url, options: .atomic)
            persistenceError = nil
        } catch {
            persistenceError = "Could not write projects.json: \(error.localizedDescription)"
        }
    }
}
