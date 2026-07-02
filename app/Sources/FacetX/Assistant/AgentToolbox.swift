import Foundation
import FacetXCore
import PDFKit

/// The assistant's tool layer: FacetX capabilities exposed as Anthropic
/// tool-use definitions (MCP-style — name + description + JSON schema), with
/// execution dispatched onto the app's real services. Kept UI-free so it can
/// later back an actual MCP server as well.
@MainActor
final class AgentToolbox {
    private weak var eventKit: EventKitService?
    private weak var projectStore: ProjectStore?
    private weak var settings: AppSettings?

    init(eventKit: EventKitService, projectStore: ProjectStore, settings: AppSettings) {
        self.eventKit = eventKit
        self.projectStore = projectStore
        self.settings = settings
    }

    // ── Definitions ──────────────────────────────────────────────────────────

    /// Anthropic `tools` array. Descriptions state *when* to call each tool,
    /// not just what it does.
    var definitions: [[String: Any]] {
        [
            tool("list_projects",
                 "List the user's active projects with their prefixes, taglines, and current week goals. Call this first whenever you need to know which projects exist or which prefix to use.",
                 properties: [:], required: []),

            tool("list_items",
                 "List calendar events and reminder tasks. Call this before answering questions about the user's schedule or workload, and before creating items (to avoid duplicates).",
                 properties: [
                    "project": prop("string", "Project name or prefix. Omit for all projects."),
                    "scope": propEnum(["today", "overdue", "this_week", "upcoming", "all"],
                                      "Time slice to return. 'upcoming' = next 14 days. Default 'this_week'."),
                    "include_completed": prop("boolean", "Include completed tasks. Default false."),
                 ], required: []),

            tool("create_task",
                 "Create a reminder task in a project. Use for to-dos and action items. Call once per task.",
                 properties: [
                    "project": prop("string", "Project name or prefix (must match an existing project)."),
                    "title": prop("string", "Task content, without the project prefix."),
                    "due_date": prop("string", "Due date YYYY-MM-DD. Omit for no date."),
                    "due_time": prop("string", "Due time HH:mm (24h). Only with due_date."),
                    "tags": ["type": "array", "items": ["type": "string"],
                             "description": "FacetX tags, without '#'."] as [String: Any],
                 ], required: ["project", "title"]),

            tool("create_event",
                 "Create a calendar event in a project. Use for meetings and scheduled time blocks (anything with a start time or a specific day).",
                 properties: [
                    "project": prop("string", "Project name or prefix (must match an existing project)."),
                    "title": prop("string", "Event content, without the project prefix."),
                    "date": prop("string", "Event date YYYY-MM-DD."),
                    "start_time": prop("string", "Start time HH:mm (24h). Omit for an all-day event."),
                    "duration_minutes": prop("integer", "Duration in minutes when start_time is set. Default 60."),
                 ], required: ["project", "title", "date"]),

            tool("create_note",
                 "Create a markdown note in a project (an all-day anchor event plus a local markdown body). Use when the user wants a plan, summary, or reference material saved as a note.",
                 properties: [
                    "project": prop("string", "Project name or prefix."),
                    "title": prop("string", "Note title, without the project prefix."),
                    "body": prop("string", "Markdown body of the note."),
                 ], required: ["project", "title", "body"]),

            tool("complete_item",
                 "Mark a reminder task as completed. Use the item id from list_items.",
                 properties: [
                    "item_id": prop("string", "The task's id as returned by list_items."),
                 ], required: ["item_id"]),

            tool("list_papers",
                 "Search the user's literature library. Call before summarizing or discussing papers to get paper ids.",
                 properties: [
                    "query": prop("string", "Match against title/authors/venue. Omit to list recent papers."),
                    "status": propEnum(["pending", "read", "starred", "skip"],
                                       "Filter by reading status. Omit for all."),
                 ], required: []),

            tool("read_paper",
                 "Read a paper's content. Call with mode 'abstract' first; use 'full_text' (optionally with a page range) when the user wants a summary or details beyond the abstract. Long PDFs are paginated — check total_pages in the result and read in chunks.",
                 properties: [
                    "paper_id": prop("string", "Paper id from list_papers."),
                    "mode": propEnum(["abstract", "full_text"], "What to read. Default 'abstract'."),
                    "page_start": prop("integer", "First PDF page to read (1-based, full_text only)."),
                    "page_end": prop("integer", "Last PDF page to read (inclusive, full_text only)."),
                 ], required: ["paper_id"]),

            tool("save_paper_note",
                 "Save a note onto a paper (e.g. a summary you produced). Appends to the existing note unless replace is true.",
                 properties: [
                    "paper_id": prop("string", "Paper id from list_papers."),
                    "note": prop("string", "Markdown note content."),
                    "replace": prop("boolean", "Replace the existing note instead of appending. Default false."),
                 ], required: ["paper_id", "note"]),
        ]
    }

    // ── Execution ────────────────────────────────────────────────────────────

    /// Execute one tool call; the returned string becomes the tool_result.
    /// Throws never — errors are returned as text so the model can adapt.
    func execute(name: String, input: [String: Any]) async -> (result: String, isError: Bool) {
        do {
            switch name {
            case "list_projects": return (try listProjects(), false)
            case "list_items": return (try await listItems(input), false)
            case "create_task": return (try await createTask(input), false)
            case "create_event": return (try await createEvent(input), false)
            case "create_note": return (try await createNote(input), false)
            case "complete_item": return (try await completeItem(input), false)
            case "list_papers": return (try listPapers(input), false)
            case "read_paper": return (try readPaper(input), false)
            case "save_paper_note": return (try savePaperNote(input), false)
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
            default:
                return true
            }
        }

        guard !items.isEmpty else { return "No items in scope '\(scope)'." }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "yyyy-MM-dd"

        let capped = items.prefix(80)
        var lines = capped.map { item -> String in
            var parts = ["[\(item.id)]"]
            parts.append(item.kind == .reminder ? (item.isCompleted ? "task(done)" : "task") : "event")
            parts.append("\(item.projectPrefix): \(item.content)")
            if let d = item.date {
                parts.append(item.hasTime && !item.isAllDay ? fmt.string(from: d) : dayFmt.string(from: d))
            }
            if item.isOverdue { parts.append("OVERDUE") }
            if !item.tags.isEmpty { parts.append("#" + item.tags.joined(separator: " #")) }
            return "- " + parts.joined(separator: " | ")
        }
        if items.count > capped.count {
            lines.append("(+\(items.count - capped.count) more items truncated)")
        }
        return lines.joined(separator: "\n")
    }

    private func parseDay(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = .current
        return fmt.date(from: raw)
    }

    private func combine(day: Date, time raw: String?) -> (date: Date, hasTime: Bool) {
        guard let raw, !raw.isEmpty else { return (day, false) }
        let parts = raw.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return (day, false) }
        let cal = Calendar.current
        let date = cal.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day) ?? day
        return (date, true)
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
        var dueDate: Date?
        var hasTime = false
        if let day = parseDay(input["due_date"] as? String) {
            (dueDate, hasTime) = {
                let combined = combine(day: day, time: input["due_time"] as? String)
                return (combined.date, combined.hasTime)
            }()
        }
        let tags = (input["tags"] as? [Any])?.compactMap { $0 as? String } ?? []
        let created = await eventKit.createReminder(
            project: project.prefix, content: title,
            listName: listName, dueDate: dueDate, dueIncludesTime: hasTime,
            tags: tags,
            enabledLists: settings.effectiveReminderListNames
        )
        guard created != nil else { throw ToolError.message("EventKit rejected the reminder.") }
        return "Created task '\(project.prefix): \(title)'" + (dueDate != nil ? " due \(input["due_date"] as? String ?? "")" : "")
    }

    private func createEvent(_ input: [String: Any]) async throws -> String {
        guard let eventKit, let settings else { throw ToolError.message("Service unavailable") }
        guard let project = try resolveProject(input["project"] as? String) else {
            throw ToolError.message("Missing 'project'.")
        }
        guard let title = input["title"] as? String, !title.isEmpty else {
            throw ToolError.message("Missing 'title'.")
        }
        guard let day = parseDay(input["date"] as? String) else {
            throw ToolError.message("Missing or invalid 'date' (YYYY-MM-DD).")
        }
        let calName = settings.calendarSaveTarget(projectCalendarName: project.calendarName)
        guard !calName.isEmpty else {
            throw ToolError.message("No calendar configured for project \(project.name).")
        }
        let (start, hasTime) = combine(day: day, time: input["start_time"] as? String)
        let duration = input["duration_minutes"] as? Int ?? 60
        let created = await eventKit.createEvent(
            project: project.prefix, content: title,
            calendarName: calName, startDate: start,
            durationMinutes: hasTime ? duration : settings.defaultEventDurationMinutes,
            tags: [],
            isAllDay: !hasTime,
            enabledCalendars: settings.effectiveCalendarNames
        )
        guard created != nil else { throw ToolError.message("EventKit rejected the event.") }
        return "Created event '\(project.prefix): \(title)' on \(input["date"] as? String ?? "")"
            + (hasTime ? " at \(input["start_time"] as? String ?? "") (\(duration) min)" : " (all day)")
    }

    private func createNote(_ input: [String: Any]) async throws -> String {
        guard let eventKit, let settings else { throw ToolError.message("Service unavailable") }
        guard let project = try resolveProject(input["project"] as? String) else {
            throw ToolError.message("Missing 'project'.")
        }
        guard let title = input["title"] as? String, !title.isEmpty,
              let body = input["body"] as? String else {
            throw ToolError.message("Missing 'title' or 'body'.")
        }
        let calName = settings.calendarSaveTarget(projectCalendarName: project.calendarName)
        guard !calName.isEmpty else {
            throw ToolError.message("No calendar configured for project \(project.name).")
        }
        let eventId = await eventKit.createNote(
            project: project.prefix, content: title,
            calendarName: calName, startDate: Calendar.current.startOfDay(for: Date()),
            dataDirectory: project.effectiveDataDirectory,
            enabledCalendars: settings.effectiveCalendarNames
        )
        guard eventId != nil else { throw ToolError.message("Could not create the note anchor event.") }
        // The anchor event carries a fresh facetID; find it to attach the body.
        let items = try await fetchItems(prefixes: [project.prefix])
        if let created = items.first(where: { $0.id == eventId }), let facetID = created.facetID {
            ItemStore.shared.save(id: facetID, body: body)
            _ = NoteStore.shared.save(dataDirectory: project.effectiveDataDirectory,
                                      facetID: facetID, body: body)
        }
        return "Created note '\(project.prefix): \(title)' with \(body.count) characters."
    }

    private func completeItem(_ input: [String: Any]) async throws -> String {
        guard let eventKit else { throw ToolError.message("Service unavailable") }
        guard let id = input["item_id"] as? String, !id.isEmpty else {
            throw ToolError.message("Missing 'item_id'.")
        }
        await eventKit.setReminderCompleted(id: id, completed: true)
        return "Marked item \(id) as completed."
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

    private func savePaperNote(_ input: [String: Any]) throws -> String {
        guard let id = input["paper_id"] as? String,
              let note = input["note"] as? String, !note.isEmpty else {
            throw ToolError.message("Missing 'paper_id' or 'note'.")
        }
        let paper = try findPaper(id)
        let replace = input["replace"] as? Bool ?? false
        let merged: String
        if replace || paper.note.isEmpty {
            merged = note
        } else {
            merged = paper.note + "\n\n---\n\n" + note
        }
        PaperStore.shared.setPaperNote(id: id, note: merged)
        return "Saved note on '\(paper.title)' (\(merged.count) characters total)."
    }

    // ── Schema helpers ───────────────────────────────────────────────────────

    private func tool(_ name: String, _ description: String,
                      properties: [String: [String: Any]], required: [String]) -> [String: Any] {
        [
            "name": name,
            "description": description,
            "input_schema": [
                "type": "object",
                "properties": properties,
                "required": required,
            ] as [String: Any],
        ]
    }

    private func prop(_ type: String, _ description: String) -> [String: Any] {
        ["type": type, "description": description]
    }

    private func propEnum(_ values: [String], _ description: String) -> [String: Any] {
        ["type": "string", "enum": values, "description": description]
    }
}
