import Foundation
import FacetXCore
import PDFKit

/// The assistant's tool layer: FacetX capabilities exposed as portable
/// tool-use definitions (MCP-style — name + description + JSON schema), with
/// execution dispatched onto the app's real services. Kept UI-free so it can
/// later back an actual MCP server as well.
@MainActor
final class AgentToolbox {
    private weak var eventKit: EventKitService?
    private weak var projectStore: ProjectStore?
    private weak var settings: AppSettings?
    private var referencedItems: [String: AssistantItemMention] = [:]

    init(eventKit: EventKitService, projectStore: ProjectStore, settings: AppSettings) {
        self.eventKit = eventKit
        self.projectStore = projectStore
        self.settings = settings
    }

    // ── Definitions ──────────────────────────────────────────────────────────

    /// Canonical tool definitions. Provider clients translate this shape to
    /// their wire format. Descriptions state when to call each tool.
    var definitions: [[String: Any]] {
        [
            tool("list_projects",
                 "List active projects and canonical prefixes. Use when the project is not explicit.",
                 properties: [:], required: []),
            tool("list_items",
                 "List FacetX items as JSON. Use reference_id for mutations; never match a title because titles can repeat. For date-range queries (e.g. completed work in a period) supply date_from and date_to and set scope to 'all'.",
                 properties: [
                    "project": nullableProp("string", "Project name/prefix, or null for all."),
                    "scope": nullableEnum(["today", "overdue", "this_week", "upcoming", "all"], "Time scope, or null for this_week. Use 'all' with date_from/date_to for explicit ranges."),
                    "date_from": nullableProp("string", "Inclusive start date YYYY-MM-DD, or null. Requires scope 'all'."),
                    "date_to": nullableProp("string", "Inclusive end date YYYY-MM-DD, or null. Requires scope 'all'."),
                    "include_completed": nullableProp("boolean", "Include completed tasks, or null for false."),
                 ], required: []),
            tool("get_item",
                 "Read one exact referenced task or event, including its local details when available.",
                 properties: [
                    "reference_id": prop("string", "Exact id from a drag reference or list_items."),
                 ], required: ["reference_id"]),
            tool("create_task",
                 "Create one reminder task. due_at is YYYY-MM-DD, local YYYY-MM-DDTHH:mm, or null. Priority applies only to tasks.",
                 properties: [
                    "project": prop("string", "Existing project name or prefix."),
                    "title": prop("string", "Task title without project prefix."),
                    "due_at": nullableProp("string", "Due date/time, or null."),
                    "priority": nullableEnum(["none", "low", "medium", "high"], "Priority, or null for none."),
                    "tags": nullableArray("string", "Tags without #, or null."),
                 ], required: ["project", "title"]),
            tool("create_event",
                 "Create one event. Timed values use local YYYY-MM-DDTHH:mm. All-day values use YYYY-MM-DD; end is exclusive and null means one day/default duration.",
                 properties: [
                    "project": prop("string", "Existing project name or prefix."),
                    "title": prop("string", "Event title without project prefix."),
                    "start": prop("string", "Inclusive start date or timestamp."),
                    "end": nullableProp("string", "Exclusive end date/timestamp, or null."),
                    "all_day": prop("boolean", "Whether this is an all-day event."),
                    "tags": nullableArray("string", "Tags without #, or null."),
                 ], required: ["project", "title", "start", "all_day"]),
            tool("list_project_documents",
                 "List README.md and .facetx Markdown documents in one project's local Git repository.",
                 properties: [
                    "project": prop("string", "Existing project name or prefix."),
                 ], required: ["project"]),
            tool("read_project_document",
                 "Read one repository document. path must be README.md or a top-level .facetx Markdown path returned by list_project_documents.",
                 properties: [
                    "project": prop("string", "Existing project name or prefix."),
                    "path": prop("string", "Repository-relative document path."),
                 ], required: ["project", "path"]),
            tool("create_project_document",
                 "Create a new Markdown document in a project's .facetx directory.",
                 properties: [
                    "project": prop("string", "Existing project name or prefix."),
                    "title": prop("string", "Document title used to create its filename."),
                    "body": prop("string", "Complete Markdown body."),
                 ], required: ["project", "title", "body"]),
            tool("update_project_document",
                 "Replace or append Markdown in an existing repository document.",
                 properties: [
                    "project": prop("string", "Existing project name or prefix."),
                    "path": prop("string", "Repository-relative document path."),
                    "body": prop("string", "Markdown content."),
                    "mode": propEnum(["replace", "append"], "Write mode."),
                 ], required: ["project", "path", "body", "mode"]),
            tool("attach_document_to_item",
                 "Attach an existing project repository document to one exact task or event.",
                 properties: [
                    "reference_id": prop("string", "Exact id from a drag reference or list_items."),
                    "path": prop("string", "Repository-relative document path."),
                 ], required: ["reference_id", "path"]),
            tool("attach_paper_to_item",
                 "Attach one literature paper to one exact task or event.",
                 properties: [
                    "reference_id": prop("string", "Exact id from a drag reference or list_items."),
                    "paper_id": prop("string", "Paper id from list_papers."),
                 ], required: ["reference_id", "paper_id"]),
            tool("update_item",
                 "Update an exact task/event. Null means keep the existing value. Event priority is unsupported.",
                 properties: [
                    "reference_id": prop("string", "Exact id from a drag reference or list_items."),
                    "title": nullableProp("string", "Replacement title, or null."),
                    "scheduled_start": nullableProp("string", "Replacement due/start date or timestamp, or null."),
                    "scheduled_end": nullableProp("string", "Replacement event end, or null."),
                    "all_day": nullableProp("boolean", "Replacement event all-day flag, or null."),
                    "priority": nullableEnum(["none", "low", "medium", "high"], "Replacement task priority, or null."),
                    "tags": nullableArray("string", "Complete replacement tags, or null."),
                 ], required: ["reference_id"]),
            tool("set_task_completion",
                 "Set the completion state of one exact reminder task.",
                 properties: [
                    "reference_id": prop("string", "Exact id from a drag reference or list_items."),
                    "completed": prop("boolean", "Desired completion state."),
                 ], required: ["reference_id", "completed"]),
            tool("delete_item",
                 "Permanently delete one exact task or event from EventKit. Irreversible — confirm with the user before calling.",
                 properties: [
                    "reference_id": prop("string", "Exact id from a drag reference or list_items."),
                 ], required: ["reference_id"]),
            tool("move_item",
                 "Move an exact task or event to a different project by rewriting its title prefix. The item's container (reminder list / calendar) is updated when possible.",
                 properties: [
                    "reference_id": prop("string", "Exact id from a drag reference or list_items."),
                    "target_project": prop("string", "Destination project name or prefix."),
                 ], required: ["reference_id", "target_project"]),
            tool("list_week_goals",
                 "Read week goals across all (or one) project. week is an ISO-8601 Monday-start week string like '2026-W22', or null for the current week.",
                 properties: [
                    "project": nullableProp("string", "Project name/prefix, or null for all projects."),
                    "week": nullableProp("string", "Week ID like '2026-W22', or null for the current week."),
                 ], required: []),
            tool("set_week_goal",
                 "Create or update a week goal for one project. week is ISO-8601 like '2026-W22', or null for the current week. Empty title clears the goal.",
                 properties: [
                    "project": prop("string", "Existing project name or prefix."),
                    "week": nullableProp("string", "Week ID like '2026-W22', or null for the current week."),
                    "title": prop("string", "Goal title. Empty string clears the goal."),
                    "body": nullableProp("string", "Optional markdown body / sub-goals, or null."),
                 ], required: ["project", "title"]),
            tool("list_papers",
                 "Search the literature library and return paper ids.",
                 properties: [
                    "query": nullableProp("string", "Title/author/venue query, or null."),
                    "status": nullableEnum(["pending", "read", "starred", "skip"], "Reading status, or null."),
                 ], required: []),
            tool("read_paper",
                 "Read a paper abstract or paginated PDF text.",
                 properties: [
                    "paper_id": prop("string", "Paper id from list_papers."),
                    "mode": nullableEnum(["abstract", "full_text"], "Read mode, or null for abstract."),
                    "page_start": nullableProp("integer", "First page, or null."),
                    "page_end": nullableProp("integer", "Last page, or null."),
                 ], required: ["paper_id"]),
        ]
    }

    // ── Execution ────────────────────────────────────────────────────────────

    /// Execute one tool call; the returned string becomes the tool_result.
    /// Throws never — errors are returned as text so the model can adapt.
    func registerReferences(_ mentions: [AssistantItemMention]) {
        for mention in mentions { referencedItems[mention.referenceID] = mention }
    }

    func execute(name: String, input: [String: Any]) async -> (result: String, isError: Bool) {
        do {
            switch name {
            case "list_projects": return (try listProjects(), false)
            case "list_items": return (try await listItems(input), false)
            case "get_item": return (try await getItem(input), false)
            case "create_task": return (try await createTask(input), false)
            case "create_event": return (try await createEvent(input), false)
            case "list_project_documents": return (try listProjectDocuments(input), false)
            case "read_project_document": return (try readProjectDocument(input), false)
            case "create_project_document": return (try createProjectDocument(input), false)
            case "update_project_document": return (try updateProjectDocument(input), false)
            case "attach_document_to_item": return (try await attachDocumentToItem(input), false)
            case "attach_paper_to_item": return (try await attachPaperToItem(input), false)
            case "update_item": return (try await updateItem(input), false)
            case "set_task_completion": return (try await setTaskCompletion(input), false)
            case "delete_item": return (try await deleteItem(input), false)
            case "move_item": return (try await moveItem(input), false)
            case "list_week_goals": return (try listWeekGoals(input), false)
            case "set_week_goal": return (try await setWeekGoal(input), false)
            case "list_papers": return (try listPapers(input), false)
            case "read_paper": return (try readPaper(input), false)
            default:
                return ("Unknown tool: \(name)", true)
            }
        } catch {
            return ("Error: \(error.localizedDescription)", true)
        }
    }

    enum ToolError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            if case .message(let m) = self { return m }
            return nil
        }
    }

    // ── Projects & items ─────────────────────────────────────────────────────

    private func listProjects() throws -> String {
        guard let projectStore else { throw ToolError.message("Service unavailable") }
        let weekId = ISOWeek.containing(Date()).id
        guard !projectStore.activeProjects.isEmpty else {
            return "No projects yet. The user must create one in FacetX first."
        }
        let lines = projectStore.activeProjects.map { project -> String in
            var line = "- \(project.name) (prefix: \(project.prefix))"
            if !project.tagline.isEmpty { line += " — \(project.tagline)" }
            if let goal = project.weekGoals.first(where: { $0.weekId == weekId }) {
                line += "\n  week goal (\(weekId)): \(goal.title)"
            }
            return line
        }
        return lines.joined(separator: "\n")
    }

    private func resolveProject(_ raw: String?) throws -> Project? {
        guard let projectStore else { throw ToolError.message("Service unavailable") }
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        let lowered = raw.lowercased()
        if let match = projectStore.activeProjects.first(where: {
            $0.name.lowercased() == lowered || $0.prefix.lowercased() == lowered
        }) {
            return match
        }
        let names = projectStore.activeProjects.map(\.name).joined(separator: ", ")
        throw ToolError.message("Project '\(raw)' not found. Active projects: \(names)")
    }

    private func fetchItems(prefixes: Set<String>) async throws -> [ProjectItem] {
        guard let eventKit, let settings else { throw ToolError.message("Service unavailable") }
        return await eventKit.items(
            forProjects: prefixes,
            enabledReminderLists: settings.effectiveReminderListNames,
            enabledCalendars: settings.effectiveCalendarNames
        )
    }

    private func listItems(_ input: [String: Any]) async throws -> String {
        guard let projectStore else { throw ToolError.message("Service unavailable") }
        let project = try resolveProject(input["project"] as? String)
        let prefixes = project.map { Set([$0.prefix]) }
            ?? Set(projectStore.activeProjects.map(\.prefix))
        guard !prefixes.isEmpty else { return "No projects configured." }

        let scope = input["scope"] as? String ?? "this_week"
        let includeCompleted = input["include_completed"] as? Bool ?? false
        let cal = Calendar.current
        let now = Date()
        let todayStart = cal.startOfDay(for: now)

        var items = try await fetchItems(prefixes: prefixes)
        if !includeCompleted {
            items = items.filter { !$0.isCompleted }
        }
        items = items.filter { item in
            switch scope {
            case "today":
                guard let d = item.date else { return false }
                return cal.isDateInToday(d)
            case "overdue":
                return item.isOverdue
            case "this_week":
                guard let d = item.date else { return item.kind == .reminder }
                let week = ISOWeek.containing(now)
                return d >= week.startDate && d < week.endDate
            case "upcoming":
                guard let d = item.date else { return item.kind == .reminder }
                return d >= todayStart && d <= cal.date(byAdding: .day, value: 14, to: todayStart)!
            default: // "all" or explicit date range
                if let fromStr = input["date_from"] as? String,
                   let toStr = input["date_to"] as? String,
                   let fromDate = parseDateValue(fromStr)?.date,
                   let toDate = parseDateValue(toStr)?.date {
                    // inclusive end: extend to end of day
                    let rangeEnd = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: toDate))!
                    if let d = item.date {
                        return d >= cal.startOfDay(for: fromDate) && d < rangeEnd
                    }
                    // undated reminders: only include when no date filter is requested
                    return false
                }
                return true
            }
        }

        let capped = Array(items.prefix(80))
        let mentions = capped.map(AssistantItemMention.init(item:))
        registerReferences(mentions)
        return jsonString([
            "items": mentions.map(\.promptObject),
            "truncated_count": max(0, items.count - capped.count),
        ])
    }

    private func parseDateValue(_ raw: String?) -> (date: Date, hasTime: Bool)? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return (date, true) }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) { return (date, true) }

        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm"] {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return (date, true) }
        }
        let day = DateFormatter()
        day.calendar = Calendar(identifier: .gregorian)
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = .current
        day.dateFormat = "yyyy-MM-dd"
        return day.date(from: raw).map { ($0, false) }
    }

    private func priorityValue(_ raw: String?) -> Int? {
        guard let raw else { return nil }
        switch raw {
        case "none": return 0
        case "low": return 9
        case "medium": return 5
        case "high": return 1
        default: return nil
        }
    }

    private func createTask(_ input: [String: Any]) async throws -> String {
        guard let eventKit, let settings else { throw ToolError.message("Service unavailable") }
        guard let project = try resolveProject(input["project"] as? String) else {
            throw ToolError.message("Missing 'project'.")
        }
        guard let title = input["title"] as? String, !title.isEmpty else {
            throw ToolError.message("Missing 'title'.")
        }
        let listName = settings.reminderSaveTarget(projectListName: project.reminderListName)
        guard !listName.isEmpty else {
            throw ToolError.message("No reminder list configured for project \(project.name).")
        }
        let due = parseDateValue(input["due_at"] as? String)
        let tags = (input["tags"] as? [Any])?.compactMap { $0 as? String } ?? []
        let priority = priorityValue(input["priority"] as? String) ?? 0
        let stableID = UUID().uuidString
        let created = await eventKit.createReminder(
            project: project.prefix, content: title,
            listName: listName, dueDate: due?.date, dueIncludesTime: due?.hasTime ?? false,
            tags: tags,
            itemReference: FacetItemReference(itemID: stableID),
            priority: priority,
            enabledLists: settings.effectiveReminderListNames
        )
        guard let created else { throw ToolError.message("EventKit rejected the reminder.") }
        return jsonString(["created": true, "reference_id": stableID, "eventkit_id": created, "type": "task"])
    }

    private func createEvent(_ input: [String: Any]) async throws -> String {
        guard let eventKit, let settings else { throw ToolError.message("Service unavailable") }
        guard let project = try resolveProject(input["project"] as? String) else {
            throw ToolError.message("Missing 'project'.")
        }
        guard let title = input["title"] as? String, !title.isEmpty else {
            throw ToolError.message("Missing 'title'.")
        }
        let allDay = input["all_day"] as? Bool ?? false
        guard let start = parseDateValue(input["start"] as? String) else {
            throw ToolError.message("Missing or invalid 'start'.")
        }
        let calName = settings.calendarSaveTarget(projectCalendarName: project.calendarName)
        guard !calName.isEmpty else {
            throw ToolError.message("No calendar configured for project \(project.name).")
        }
        let end = parseDateValue(input["end"] as? String)?.date
        if let end, end <= start.date {
            throw ToolError.message("Event end must be after start.")
        }
        let tags = (input["tags"] as? [Any])?.compactMap { $0 as? String } ?? []
        let duration = end.map { max(1, Int($0.timeIntervalSince(start.date) / 60)) }
            ?? settings.defaultEventDurationMinutes
        let stableID = UUID().uuidString
        let created = await eventKit.createEvent(
            project: project.prefix, content: title,
            calendarName: calName, startDate: start.date,
            durationMinutes: duration,
            tags: tags,
            itemReference: FacetItemReference(itemID: stableID),
            isAllDay: allDay,
            endDate: end,
            enabledCalendars: settings.effectiveCalendarNames
        )
        guard let created else { throw ToolError.message("EventKit rejected the event.") }
        return jsonString(["created": true, "reference_id": stableID, "eventkit_id": created, "type": "event"])
    }

    private func resolveReference(_ raw: String?) async throws -> AssistantItemMention {
        guard let raw, !raw.isEmpty else { throw ToolError.message("Missing 'reference_id'.") }
        if let mention = referencedItems[raw] {
            if let stableID = mention.stableID {
                let current = try await fetchItems(prefixes: [mention.projectPrefix])
                    .first { $0.facetID == stableID }
                if let current {
                    let refreshed = AssistantItemMention(item: current)
                    referencedItems[raw] = refreshed
                    return refreshed
                }
            }
            return mention
        }
        guard let projectStore else { throw ToolError.message("Service unavailable") }
        let prefixes = Set(projectStore.activeProjects.map(\.prefix))
        let items = try await fetchItems(prefixes: prefixes)
        if let item = items.first(where: {
            $0.facetID == raw || $0.id == raw || "eventkit:\($0.id)" == raw
        }) {
            let mention = AssistantItemMention(item: item)
            referencedItems[mention.referenceID] = mention
            return mention
        }
        throw ToolError.message("Unknown reference_id '\(raw)'. Refresh with list_items or drag the item again.")
    }

    private func getItem(_ input: [String: Any]) async throws -> String {
        let mention = try await resolveReference(input["reference_id"] as? String)
        var object = mention.promptObject
        if let stableID = mention.stableID {
            let body = ItemStore.shared.body(for: stableID)
            if !body.isEmpty { object["body"] = body }
        }
        return jsonString(object)
    }

    private func updateItem(_ input: [String: Any]) async throws -> String {
        guard let eventKit else { throw ToolError.message("Service unavailable") }
        let mention = try await resolveReference(input["reference_id"] as? String)
        let title = (input["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let title, title.isEmpty { throw ToolError.message("Title cannot be empty.") }

        let parsedStart = parseDateValue(input["scheduled_start"] as? String)
        let parsedEnd = parseDateValue(input["scheduled_end"] as? String)
        let allDay = input["all_day"] as? Bool
        let priorityRaw = input["priority"] as? String
        if mention.kind == "event", priorityRaw != nil {
            throw ToolError.message("Calendar events do not support priority.")
        }
        let tags = (input["tags"] as? [Any])?.compactMap { $0 as? String }
        let start = parsedStart?.date ?? mention.date
        if mention.kind == "event", start == nil {
            throw ToolError.message("An event must have a scheduled_start.")
        }
        let success = await eventKit.updateItem(
            id: mention.eventKitID,
            project: mention.projectPrefix,
            content: title ?? mention.title,
            date: start,
            useDate: mention.kind == "event" || start != nil,
            dateIncludesTime: parsedStart?.hasTime ?? mention.hasTime,
            containerName: mention.containerName,
            tags: tags,
            priority: priorityValue(priorityRaw) ?? mention.priority,
            isAllDay: mention.kind == "event" ? (allDay ?? mention.isAllDay) : nil,
            endDate: mention.kind == "event" ? (parsedEnd?.date ?? mention.endDate) : nil
        )
        guard success else { throw ToolError.message("EventKit rejected the item update.") }
        return jsonString(["updated": true, "reference_id": mention.referenceID])
    }

    private func setTaskCompletion(_ input: [String: Any]) async throws -> String {
        guard let eventKit else { throw ToolError.message("Service unavailable") }
        let mention = try await resolveReference(input["reference_id"] as? String)
        guard mention.kind == "task" else {
            throw ToolError.message("Only reminder tasks have a completion state.")
        }
        guard let completed = input["completed"] as? Bool else {
            throw ToolError.message("Missing 'completed'.")
        }
        await eventKit.setReminderCompleted(id: mention.eventKitID, completed: completed)
        return jsonString([
            "updated": true,
            "reference_id": mention.referenceID,
            "completed": completed,
        ])
    }

    // ── Delete / move ────────────────────────────────────────────────────────

    private func deleteItem(_ input: [String: Any]) async throws -> String {
        guard let eventKit else { throw ToolError.message("Service unavailable") }
        let mention = try await resolveReference(input["reference_id"] as? String)
        let deleted = await eventKit.deleteItem(id: mention.eventKitID)
        guard deleted else { throw ToolError.message("EventKit could not delete the item.") }
        ItemStore.shared.deleteLocalState(for: mention.stableID ?? mention.eventKitID)
        referencedItems.removeValue(forKey: mention.referenceID)
        return jsonString(["deleted": true, "reference_id": mention.referenceID])
    }

    private func moveItem(_ input: [String: Any]) async throws -> String {
        guard let eventKit, let settings else { throw ToolError.message("Service unavailable") }
        let mention = try await resolveReference(input["reference_id"] as? String)
        guard let target = try resolveProject(input["target_project"] as? String) else {
            throw ToolError.message("Missing 'target_project'.")
        }
        guard mention.projectPrefix != target.prefix else {
            return jsonString(["moved": false, "reason": "Item is already in that project."])
        }
        // Determine the right container for the target project
        let newContainer: String
        if mention.kind == "task" {
            newContainer = settings.reminderSaveTarget(projectListName: target.reminderListName)
            guard !newContainer.isEmpty else {
                throw ToolError.message("No reminder list configured for project \(target.name).")
            }
        } else {
            newContainer = settings.calendarSaveTarget(projectCalendarName: target.calendarName)
            guard !newContainer.isEmpty else {
                throw ToolError.message("No calendar configured for project \(target.name).")
            }
        }
        let success = await eventKit.updateItem(
            id: mention.eventKitID,
            project: target.prefix,
            content: mention.title,
            date: mention.date,
            useDate: mention.kind == "event" || mention.date != nil,
            dateIncludesTime: mention.hasTime,
            containerName: newContainer,
            tags: nil,
            priority: mention.priority,
            isAllDay: mention.kind == "event" ? mention.isAllDay : nil,
            endDate: mention.kind == "event" ? mention.endDate : nil
        )
        guard success else { throw ToolError.message("EventKit rejected the move.") }
        return jsonString([
            "moved": true,
            "reference_id": mention.referenceID,
            "from_project": mention.projectPrefix,
            "to_project": target.prefix,
        ])
    }

    // ── Week goals ───────────────────────────────────────────────────────────

    private func listWeekGoals(_ input: [String: Any]) throws -> String {
        guard let projectStore else { throw ToolError.message("Service unavailable") }
        let weekRaw = input["week"] as? String
        let week = parseISOWeek(weekRaw) ?? ISOWeek.containing(Date())
        let projects: [Project]
        if let project = try resolveProject(input["project"] as? String) {
            projects = [project]
        } else {
            projects = projectStore.activeProjects
        }
        let lines = projects.compactMap { project -> String? in
            guard let goal = project.weekGoals.first(where: { $0.weekId == week.id }) else {
                return nil
            }
            var line = "- \(project.name) (\(week.id)): \(goal.title)"
            if !goal.body.isEmpty { line += "\n  \(goal.body)" }
            return line
        }
        if lines.isEmpty {
            return "No week goals set for \(week.id)."
        }
        return "Week goals for \(week.id):\n" + lines.joined(separator: "\n")
    }

    private func setWeekGoal(_ input: [String: Any]) async throws -> String {
        guard let projectStore, let eventKit, let settings else {
            throw ToolError.message("Service unavailable")
        }
        guard let project = try resolveProject(input["project"] as? String) else {
            throw ToolError.message("Missing 'project'.")
        }
        guard let title = input["title"] as? String else {
            throw ToolError.message("Missing 'title'.")
        }
        let weekRaw = input["week"] as? String
        let week = parseISOWeek(weekRaw) ?? ISOWeek.containing(Date())
        let body = (input["body"] as? String) ?? ""
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)

        // Sync to EventKit goal event if calendar is configured
        var eventId: String? = project.weekGoals.first(where: { $0.weekId == week.id })?.eventId
        if !trimmedTitle.isEmpty {
            let calName = project.weekGoalCalendarName ?? settings.weekGoalCalendarName
            if !calName.isEmpty {
                let newId = await eventKit.createOrUpdateGoalEvent(
                    project: project.prefix,
                    title: trimmedTitle,
                    body: body,
                    week: week,
                    calendarName: calName,
                    existingEventId: eventId,
                    enabledCalendars: settings.effectiveCalendarNames
                )
                if let newId { eventId = newId }
            }
        }
        projectStore.setWeekGoal(projectID: project.id, weekId: week.id,
                                 title: trimmedTitle, body: body, eventId: eventId)
        if trimmedTitle.isEmpty {
            return jsonString(["cleared": true, "project": project.name, "week": week.id])
        }
        return jsonString(["set": true, "project": project.name, "week": week.id, "title": trimmedTitle])
    }

    // ── Repository documents ────────────────────────────────────────────────

    private func requireProject(_ input: [String: Any]) throws -> Project {
        guard let project = try resolveProject(input["project"] as? String) else {
            throw ToolError.message("Missing 'project'.")
        }
        return project
    }

    private func listProjectDocuments(_ input: [String: Any]) throws -> String {
        let project = try requireProject(input)
        let documents = try RepositoryDocumentStore.list(repositoryPath: project.githubLocalPath)
        return jsonString([
            "project": project.name,
            "documents": documents.map {
                ["path": $0.relativePath, "title": $0.title, "is_readme": $0.isReadme] as [String: Any]
            },
        ])
    }

    private func readProjectDocument(_ input: [String: Any]) throws -> String {
        let project = try requireProject(input)
        guard let path = input["path"] as? String else {
            throw ToolError.message("Missing 'path'.")
        }
        var body = try RepositoryDocumentStore.read(
            repositoryPath: project.githubLocalPath,
            relativePath: path
        )
        if body.count > 28_000 {
            body = String(body.prefix(28_000)) + "\n…(truncated)"
        }
        return jsonString(["project": project.name, "path": path, "body": body])
    }

    private func createProjectDocument(_ input: [String: Any]) throws -> String {
        let project = try requireProject(input)
        guard let title = input["title"] as? String,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let body = input["body"] as? String else {
            throw ToolError.message("Missing 'title' or 'body'.")
        }
        let document = try RepositoryDocumentStore.create(
            repositoryPath: project.githubLocalPath,
            title: title,
            body: body
        )
        return jsonString([
            "created": true,
            "project": project.name,
            "path": document.relativePath,
        ])
    }

    private func updateProjectDocument(_ input: [String: Any]) throws -> String {
        let project = try requireProject(input)
        guard let path = input["path"] as? String,
              let body = input["body"] as? String,
              let mode = input["mode"] as? String else {
            throw ToolError.message("Missing 'path', 'body', or 'mode'.")
        }
        let existing = try RepositoryDocumentStore.read(
            repositoryPath: project.githubLocalPath,
            relativePath: path
        )
        let merged = mode == "append" && !existing.isEmpty
            ? existing + "\n\n" + body
            : body
        try RepositoryDocumentStore.save(
            repositoryPath: project.githubLocalPath,
            relativePath: path,
            body: merged
        )
        return jsonString(["updated": true, "project": project.name, "path": path, "characters": merged.count])
    }

    private func attachDocumentToItem(_ input: [String: Any]) async throws -> String {
        let mention = try await resolveReference(input["reference_id"] as? String)
        guard let stableID = mention.stableID else {
            throw ToolError.message("The referenced item has no FacetX id.")
        }
        guard let path = input["path"] as? String else {
            throw ToolError.message("Missing 'path'.")
        }
        guard let project = try resolveProject(mention.projectPrefix) else {
            throw ToolError.message("The item's project no longer exists.")
        }
        guard RepositoryDocumentStore.exists(repositoryPath: project.githubLocalPath, relativePath: path) else {
            throw ToolError.message("Document '\(path)' does not exist in project \(project.name).")
        }
        var paths = ItemStore.shared.documentPaths(for: stableID)
        if !paths.contains(path) {
            paths.append(path)
            ItemStore.shared.setDocumentPaths(paths, for: stableID)
        }
        return jsonString(["attached": true, "reference_id": mention.referenceID, "path": path])
    }

    private func attachPaperToItem(_ input: [String: Any]) async throws -> String {
        let mention = try await resolveReference(input["reference_id"] as? String)
        guard let stableID = mention.stableID else {
            throw ToolError.message("The referenced item has no FacetX id.")
        }
        guard let paperID = input["paper_id"] as? String else {
            throw ToolError.message("Missing 'paper_id'.")
        }
        let paper = try findPaper(paperID)
        var paperIDs = ItemStore.shared.paperIDs(for: stableID)
        if !paperIDs.contains(paperID) {
            paperIDs.append(paperID)
            ItemStore.shared.setPaperIDs(paperIDs, for: stableID)
        }
        return jsonString([
            "attached": true,
            "reference_id": mention.referenceID,
            "paper_id": paperID,
            "paper_title": paper.title,
        ])
    }

    // ── Literature ───────────────────────────────────────────────────────────

    private func listPapers(_ input: [String: Any]) throws -> String {
        let store = PaperStore.shared
        var papers = store.papers
        if let statusRaw = input["status"] as? String,
           let status = PaperStatus(rawValue: statusRaw) {
            papers = papers.filter { $0.status == status }
        }
        if let query = (input["query"] as? String)?.lowercased(), !query.isEmpty {
            papers = papers.filter { paper in
                paper.title.lowercased().contains(query)
                    || paper.authors.joined(separator: " ").lowercased().contains(query)
                    || paper.venue.lowercased().contains(query)
                    || paper.venueAbbr.lowercased().contains(query)
            }
        }
        guard !papers.isEmpty else { return "No matching papers." }
        let lines = papers.prefix(40).map { paper -> String in
            var parts = ["[\(paper.id)]", paper.title]
            if !paper.authors.isEmpty { parts.append(paper.authors.prefix(3).joined(separator: ", ")) }
            if let year = paper.publicationYear { parts.append(String(year)) }
            if !paper.venueAbbr.isEmpty { parts.append(paper.venueAbbr) }
            parts.append("status:\(paper.status.rawValue)")
            parts.append(paper.pdfLocalPath != nil ? "pdf:yes" : "pdf:no")
            return "- " + parts.joined(separator: " | ")
        }
        var out = lines.joined(separator: "\n")
        if papers.count > 40 { out += "\n(+\(papers.count - 40) more, refine the query)" }
        return out
    }

    private func findPaper(_ id: String) throws -> Paper {
        guard let paper = PaperStore.shared.papers.first(where: { $0.id == id }) else {
            throw ToolError.message("Paper '\(id)' not found — use list_papers to get valid ids.")
        }
        return paper
    }

    private func readPaper(_ input: [String: Any]) throws -> String {
        guard let id = input["paper_id"] as? String else {
            throw ToolError.message("Missing 'paper_id'.")
        }
        let paper = try findPaper(id)
        let mode = input["mode"] as? String ?? "abstract"

        var header = "Title: \(paper.title)\nAuthors: \(paper.authors.joined(separator: ", "))"
        if !paper.venue.isEmpty { header += "\nVenue: \(paper.venue)" }
        if !paper.publicationDate.isEmpty { header += "\nDate: \(paper.publicationDate)" }

        if mode == "abstract" {
            let abstract = paper.abstract.isEmpty ? "(no abstract on file)" : paper.abstract
            return "\(header)\n\nAbstract:\n\(abstract)"
        }

        guard let path = paper.pdfLocalPath,
              let document = PDFDocument(url: URL(fileURLWithPath: path)) else {
            let abstract = paper.abstract.isEmpty ? "(no abstract either)" : paper.abstract
            return "\(header)\n\nNo local PDF available; abstract only:\n\(abstract)"
        }

        let total = document.pageCount
        let start = max((input["page_start"] as? Int ?? 1), 1)
        let end = min(input["page_end"] as? Int ?? min(start + 9, total), total)
        guard start <= end else {
            throw ToolError.message("Invalid page range (document has \(total) pages).")
        }

        var text = ""
        for index in (start - 1)..<end {
            guard let page = document.page(at: index), let pageText = page.string else { continue }
            text += "\n--- page \(index + 1) ---\n" + pageText
        }
        let maxChars = 28000
        if text.count > maxChars {
            text = String(text.prefix(maxChars)) + "\n…(truncated — request a narrower page range)"
        }
        return "\(header)\ntotal_pages: \(total), returned pages \(start)-\(end)\n\(text)"
    }

    /// Parse an ISO-8601 week string like "2026-W22" into an ISOWeek.
    private func parseISOWeek(_ raw: String?) -> ISOWeek? {
        guard let raw else { return nil }
        let parts = raw.split(separator: "-W", maxSplits: 1)
        guard parts.count == 2,
              let year = Int(parts[0]),
              let week = Int(parts[1]) else { return nil }
        return ISOWeek(year: year, week: week)
    }

    // ── Schema helpers ───────────────────────────────────────────────────────


    private func tool(_ name: String, _ description: String,
                      properties: [String: [String: Any]], required _: [String]) -> [String: Any] {
        [
            "name": name,
            "description": description,
            "input_schema": [
                "type": "object",
                "properties": properties,
                // Strict function calling requires every property to be listed;
                // semantic optionals are represented as nullable types.
                "required": properties.keys.sorted(),
                "additionalProperties": false,
            ] as [String: Any],
        ]
    }

    private func prop(_ type: String, _ description: String) -> [String: Any] {
        ["type": type, "description": description]
    }

    private func propEnum(_ values: [String], _ description: String) -> [String: Any] {
        ["type": "string", "enum": values, "description": description]
    }

    private func nullableProp(_ type: String, _ description: String) -> [String: Any] {
        ["type": [type, "null"], "description": description]
    }

    private func nullableEnum(_ values: [String], _ description: String) -> [String: Any] {
        [
            "type": ["string", "null"],
            "enum": values.map { $0 as Any } + [NSNull()],
            "description": description,
        ]
    }

    private func nullableArray(_ itemType: String, _ description: String) -> [String: Any] {
        [
            "type": ["array", "null"],
            "items": ["type": itemType],
            "description": description,
        ]
    }

    private func jsonString(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}
