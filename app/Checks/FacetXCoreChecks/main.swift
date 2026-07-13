import FacetXCore
import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

check(ProjectPrefix.projectName(of: "Regulus: fix bug") == "Regulus",
      "ASCII colon prefix should parse")
check(ProjectPrefix.projectName(of: "Regulus：fix bug") == "Regulus",
      "Fullwidth colon prefix should parse")
check(ProjectPrefix.projectName(of: "Regulus: first\nOther: second") == "Regulus",
      "Prefix parser should only inspect first line")
check(ProjectPrefix.contentBody(of: "Regulus： fix bug") == "fix bug",
      "contentBody should strip colon-tolerant prefix")
check(ProjectPrefix.contentBody(of: "plain title\nRegulus: second") == "plain title\nRegulus: second",
      "contentBody should not strip a prefix from later lines")
check(ProjectPrefix.makeTitle(project: "Regulus", content: "fix bug") == "Regulus: fix bug",
      "makeTitle should write ASCII colon")

let week = ISOWeek(year: 2026, week: 22)
let calendar = Calendar(identifier: .iso8601)
guard let monday = calendar.date(from: DateComponents(year: 2026, month: 5, day: 25)),
      let sunday = calendar.date(from: DateComponents(year: 2026, month: 5, day: 31, hour: 23)),
      let nextMonday = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)) else {
    fatalError("Could not create test dates")
}

check(week.contains(monday), "ISO week should contain Monday start")
check(week.contains(sunday), "ISO week should contain Sunday")
check(!week.contains(nextMonday), "ISO week should exclude next Monday")
check(ISOWeek(year: 2026, week: 22).shifted(by: 1).id == "2026-W23",
      "shifted week should preserve ISO identity")

let goalTitle = WeekGoalEvent.makeTitle(project: "Regulus", title: "Ship beta")
check(goalTitle == "Regulus: Ship beta", "week goal title should stay human-readable")
let goalNotes = WeekGoalEvent.makeNotes(body: "Focus on polish", project: "Regulus", weekID: week.id)
check(WeekGoalEvent.body(fromNotes: goalNotes) == "Focus on polish",
      "week goal notes body should hide metadata")
check(WeekGoalEvent.hasGoalMetadata(goalNotes, project: "Regulus", weekID: week.id),
      "week goal notes should include identity metadata")

// ── FacetMetadata ────────────────────────────────────────────────────────────

let plainMetadata = FacetMetadata.parse(notes: "A plain note")
check(plainMetadata.userNotes == "A plain note", "plain notes should stay user-facing")
check(plainMetadata.tags.isEmpty, "plain notes should not have tags")

let nativeNotes = "Discuss scope\n\nFacetX-Metadata-Begin\ntags: deep, waiting, Deep\ncustom: keep me\nFacetX-Metadata-End"
let parsedMetadata = FacetMetadata.parse(notes: nativeNotes)
check(parsedMetadata.userNotes == "Discuss scope", "metadata block should be stripped from user notes")
check(parsedMetadata.tags == ["deep", "waiting"], "tags should trim and de-duplicate case-insensitively")
check(parsedMetadata.fields["custom"] == "keep me", "unknown metadata fields should be preserved")

let recomposed = FacetMetadata.compose(userNotes: "Updated", metadata: FacetMetadata(userNotes: "", tags: ["ship"], fields: parsedMetadata.fields)) ?? ""
check(recomposed.contains("tags: ship"), "compose should write updated tags")
check(recomposed.contains("custom: keep me"), "compose should preserve unknown fields")
check(FacetMetadata.compose(userNotes: "  ", metadata: FacetMetadata()) == nil,
      "empty notes and metadata should compose to nil")
check(FacetMetadata.tags(from: "#deep, waiting\nship") == ["deep", "waiting", "ship"],
      "tag parser should accept hashes, commas, and newlines")

let itemMetadata = FacetItemMetadata(
    itemID: "12345678-ABCD-EF01-2345-6789ABCDEF01",
    paperIDs: ["https://openalex.org/W1", "doi:10.1/a,b"],
    commits: ["owner/repo@abcdef", "owner/repo@abcdef"],
    tags: ["read"]
)
let itemNotesRepresentation = itemMetadata.itemID
let parsedItemMetadata = FacetItemMetadata.parse(notes: itemNotesRepresentation)
check(parsedItemMetadata?.itemID == "12345678-ABCD-EF01-2345-6789ABCDEF01", "item metadata should preserve stable item id")

let legacyNotes = "FacetX-Metadata-Begin\nfacetx-kind: item-v1\nitem-id: legacy-id-123\nnote-id: legacy-note-456\nFacetX-Metadata-End"
let parsedLegacy = FacetItemMetadata.parse(notes: legacyNotes)
check(parsedLegacy?.itemID == "legacy-id-123", "legacy metadata block parsing should extract item ID")
let noteKindNotes = "FacetX-Metadata-Begin\nitem-id: note-id-123\nkind: note\nFacetX-Metadata-End"
let parsedNoteKind = FacetItemMetadata.parse(notes: noteKindNotes)
check(parsedNoteKind?.itemID == "note-id-123", "note metadata should preserve item ID")
check(parsedNoteKind?.kind == .note, "note metadata should preserve facet kind")
let june = MonthYear(year: 2026, month: 6)
guard let juneStart = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)),
      let juneEnd = calendar.date(from: DateComponents(year: 2026, month: 6, day: 30, hour: 23)),
      let julyStart = calendar.date(from: DateComponents(year: 2026, month: 7, day: 1)) else {
    fatalError("Could not create month test dates")
}

check(june.id == "2026-06", "month id should be zero-padded")
check(june.firstWeekdayOffset == 0, "June 2026 should start on Monday")
check(june.contains(juneStart), "month should contain its first day")
check(june.contains(juneEnd), "month should contain its last day")
check(!june.contains(julyStart), "month should exclude next month start")
check(MonthYear(year: 2026, month: 12).shifted(by: 1).id == "2027-01",
      "shifted month should cross year boundaries")

// ── ItemArrangement ──────────────────────────────────────────────────────────

func makeItem(_ id: String, zone: String = "Inbox", done: Bool = false,
              month: Int = 5, day: Int? = nil) -> ProjectItem {
    let date = day.flatMap { calendar.date(from: DateComponents(year: 2026, month: month, day: $0)) }
    return ProjectItem(id: id, kind: .reminder, rawTitle: id, projectPrefix: "Test", content: id,
                        containerName: zone, isCompleted: done, date: date,
                        notes: nil, priority: 0, url: nil)
}

// arranged: incomplete before completed, regardless of saved order.
let arranged1 = ItemArrangement.arranged(
    [makeItem("a", done: true), makeItem("b")], savedOrder: ["a", "b"])
check(arranged1.map(\.id) == ["b", "a"], "arranged should put incomplete before completed")

// arranged: among incomplete, follow the saved manual order.
let arranged2 = ItemArrangement.arranged(
    [makeItem("x"), makeItem("y"), makeItem("z")], savedOrder: ["z", "x", "y"])
check(arranged2.map(\.id) == ["z", "x", "y"], "arranged should follow saved order")

// arranged: items absent from saved order fall back to date order, after ranked ones.
let arranged3 = ItemArrangement.arranged(
    [makeItem("late", day: 20), makeItem("early", day: 10), makeItem("ranked")],
    savedOrder: ["ranked"])
check(arranged3.map(\.id) == ["ranked", "early", "late"],
      "arranged should rank saved items first, then order the rest by date")

// groupedByZone: groups sorted by zone, each group keeps incoming order.
let groups = ItemArrangement.groupedByZone(
    [makeItem("b1", zone: "Build"), makeItem("a1", zone: "Admin"),
     makeItem("b2", zone: "Build")])
check(groups.map(\.zone) == ["Admin", "Build"], "groups should sort by zone name")
check(groups.last?.items.map(\.id) == ["b1", "b2"], "group should preserve item order")

// inWeek: keep only items dated within the week, ordered by date.
let weekItems = ItemArrangement.inWeek(
    [makeItem("out", day: 1), makeItem("sun", day: 31), makeItem("mon", day: 25)],
    ISOWeek(year: 2026, week: 22))
check(weekItems.map(\.id) == ["mon", "sun"], "inWeek should filter to the week and sort by date")

// inMonth: keep only items dated within the month, ordered by date.
let monthItems = ItemArrangement.inMonth(
    [makeItem("may", month: 5, day: 31), makeItem("jun2", month: 6, day: 2),
     makeItem("jul", month: 7, day: 1), makeItem("jun1", month: 6, day: 1)],
    MonthYear(year: 2026, month: 6))
check(monthItems.map(\.id) == ["jun1", "jun2"],
      "inMonth should filter to the month and sort by date")

// ── ProjectItem.matches ──────────────────────────────────────────────────────

let searchItem = ProjectItem(id: "s", kind: .reminder, rawTitle: "Regulus: Ship beta",
                              projectPrefix: "Regulus", content: "Ship beta", containerName: "Build",
                              isCompleted: false, date: nil, notes: "needs review", tags: ["Deep"], priority: 0, url: nil)
check(searchItem.matches(searchQuery: ""), "empty query should match everything")
check(searchItem.matches(searchQuery: "  "), "whitespace query should match everything")
check(searchItem.matches(searchQuery: "SHIP"), "matches should be case-insensitive on content")
check(searchItem.matches(searchQuery: "review"), "matches should search notes")
check(searchItem.matches(searchQuery: "deep"), "matches should search tags")
check(searchItem.matches(searchQuery: "build"), "matches should search container name")
check(!searchItem.matches(searchQuery: "missing"), "non-matching query should not match")
let resourceItem = ProjectItem(id: "meta", kind: .event, rawTitle: "Regulus: Paper",
                               projectPrefix: "Regulus", content: "Paper", containerName: "Calendar",
                               isCompleted: false, date: nil, notes: nil, tags: ["Reading"],
                               priority: 0, url: nil,
                               facetID: "stable-item",
                               linkedPaperIDs: ["paper-1"], linkedCommits: ["owner/repo@abc"],
                               linkedDocumentPaths: [".facetx/plan.md"])
let searchItemMetadata = resourceItem.facetItemMetadata()
check(searchItemMetadata.itemID == "stable-item", "item metadata helper should preserve item id")
check(searchItemMetadata.paperIDs == ["paper-1"], "item metadata helper should preserve papers")
check(searchItemMetadata.commits == ["owner/repo@abc"], "item metadata helper should preserve commits")
check(searchItemMetadata.tags == ["Reading"], "item metadata helper should preserve tags")
let replacementDate = calendar.date(from: DateComponents(year: 2026, month: 6, day: 4))!
let replacedSearchItem = searchItem.replacingDate(replacementDate)
check(replacedSearchItem.date == replacementDate, "replacingDate should update the item date")
check(replacedSearchItem.id == searchItem.id && replacedSearchItem.content == searchItem.content,
      "replacingDate should preserve item identity and content")
check(resourceItem.replacingDate(replacementDate).linkedDocumentPaths == [".facetx/plan.md"],
      "item copies should preserve linked documents")
let timedSearchItem = searchItem.replacingDate(replacementDate, hasTime: true)
check(timedSearchItem.hasTime, "replacingDate should allow marking a date as timed")
check(timedSearchItem.replacingDate(replacementDate).hasTime,
      "replacingDate should preserve timed-date state by default")

// ── ItemQuery ────────────────────────────────────────────────────────────────

let queryEvent = ProjectItem(id: "event", kind: .event, rawTitle: "Regulus: Demo",
                             projectPrefix: "Regulus", content: "Demo", containerName: "Calendar",
                             isCompleted: false, date: nil, notes: nil, priority: 0, url: nil)
let queryDone = ProjectItem(id: "done", kind: .reminder, rawTitle: "Regulus: Done",
                            projectPrefix: "Regulus", content: "Done", containerName: "Build",
                            isCompleted: true, date: nil, notes: "archived", tags: ["Done"],
                            priority: 0, url: nil)
let queryOpen = ProjectItem(id: "open", kind: .reminder, rawTitle: "Nova: Ship",
                            projectPrefix: "Nova", content: "Ship", containerName: "Inbox",
                            isCompleted: false, date: nil, notes: "needs review", tags: ["Deep"],
                            priority: 0, url: nil)

let queryItems = [queryEvent, queryDone, queryOpen]
check(ItemQuery.searched(queryItems, query: "").map(\.id) == ["event", "done", "open"],
      "searched should keep everything for an empty query")
check(ItemQuery.searched(queryItems, query: "SHIP").map(\.id) == ["open"],
      "searched should match content case-insensitively")
check(ItemQuery.searched(queryItems, query: "review").map(\.id) == ["open"],
      "searched should match notes")
check(ItemQuery.searched(queryItems, query: "deep").map(\.id) == ["open"],
      "searched should match tags")
check(ItemQuery.searched(queryItems, query: "calendar").map(\.id) == ["event"],
      "searched should match container names")

check(ItemQuery.completedVisibility(queryItems, showCompleted: false).map(\.id) == ["event", "open"],
      "completedVisibility should hide completed reminders but keep events")
check(ItemQuery.completedVisibility(queryItems, showCompleted: true).map(\.id) == ["event", "done", "open"],
      "completedVisibility should keep all items when requested")

let now = Date()
let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86_400)
let todayOpen = ProjectItem(id: "today-open", kind: .reminder, rawTitle: "Regulus: Today",
                            projectPrefix: "Regulus", content: "Today", containerName: "Inbox",
                            isCompleted: false, date: now, notes: nil, priority: 0, url: nil)
let todayDone = ProjectItem(id: "today-done", kind: .reminder, rawTitle: "Regulus: Done Today",
                            projectPrefix: "Regulus", content: "Done Today", containerName: "Inbox",
                            isCompleted: true, date: now, notes: nil, priority: 0, url: nil)
let todayEvent = ProjectItem(id: "today-event", kind: .event, rawTitle: "Nova: Demo",
                             projectPrefix: "Nova", content: "Demo", containerName: "Calendar",
                             isCompleted: false, date: now, notes: nil, priority: 0, url: nil)
let tomorrowOpen = ProjectItem(id: "tomorrow-open", kind: .reminder, rawTitle: "Regulus: Tomorrow",
                               projectPrefix: "Regulus", content: "Tomorrow", containerName: "Inbox",
                               isCompleted: false, date: tomorrow, notes: nil, priority: 0, url: nil)
check(ItemQuery.todayItems([todayOpen, todayDone, todayEvent, tomorrowOpen]).map(\.id) == ["today-open", "today-event"],
      "todayItems should include today's dated items and exclude completed reminders by default")
check(ItemQuery.todayItems([todayOpen, todayDone, todayEvent], includeCompletedReminders: true).map(\.id) == ["today-open", "today-done", "today-event"],
      "todayItems should include completed reminders when requested")

let filterNow = calendar.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 12))!
let filterToday = calendar.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 18))!
let filterNextWeek = calendar.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 9))!
let filterAfterWeek = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 9))!
let filterTask = ProjectItem(id: "filter-task", kind: .reminder, rawTitle: "Regulus: Task",
                             projectPrefix: "Regulus", content: "Task", containerName: "Inbox",
                             isCompleted: false, date: filterToday, notes: nil, priority: 0, url: nil)
let filterEvent = ProjectItem(id: "filter-event", kind: .event, rawTitle: "Regulus: Event",
                              projectPrefix: "Regulus", content: "Event", containerName: "Calendar",
                              isCompleted: false, date: filterNextWeek, notes: nil, priority: 0, url: nil)
let filterLater = ProjectItem(id: "filter-later", kind: .reminder, rawTitle: "Regulus: Later",
                              projectPrefix: "Regulus", content: "Later", containerName: "Inbox",
                              isCompleted: false, date: filterAfterWeek, notes: nil, priority: 0, url: nil)
let filterUndated = ProjectItem(id: "filter-undated", kind: .reminder, rawTitle: "Regulus: Undated",
                                projectPrefix: "Regulus", content: "Undated", containerName: "Inbox",
                                isCompleted: false, date: nil, notes: nil, priority: 0, url: nil)
let filterItems = [filterTask, filterEvent, filterLater, filterUndated]
check(ItemQuery.filtered(filterItems, by: ItemListFilter(kindScope: .tasks), now: filterNow, calendar: calendar).map(\.id) == ["filter-task", "filter-later", "filter-undated"],
      "item filter should keep only tasks when task scope is selected")
check(ItemQuery.filtered(filterItems, by: ItemListFilter(kindScope: .events), now: filterNow, calendar: calendar).map(\.id) == ["filter-event"],
      "item filter should keep only events when schedule scope is selected")
check(ItemQuery.filtered(filterItems, by: ItemListFilter(dateScope: .today), now: filterNow, calendar: calendar).map(\.id) == ["filter-task"],
      "item filter should keep only today's dated items")
check(ItemQuery.filtered(filterItems, by: ItemListFilter(dateScope: .nextSevenDays), now: filterNow, calendar: calendar).map(\.id) == ["filter-task", "filter-event"],
      "item filter should keep dated items in the next seven days")

let counts = ItemQuery.counts(for: queryItems)
check(counts.taskOpenCount == 1, "counts should include open tasks")
check(counts.taskCompletedCount == 1, "counts should include completed tasks")
check(counts.eventCount == 1, "counts should include events")
check(ItemQuery.projectPrefixCount(for: [todayOpen, todayEvent, tomorrowOpen]) == 2,
      "projectPrefixCount should count distinct project prefixes")

// ── FacetAssociation ─────────────────────────────────────────────────────────

check(FacetAssociation.classify(title: "Regulus: fix bug") == .item(projectPrefix: "Regulus", content: "fix bug"),
      "classify should return item for regular title")
check(FacetAssociation.classify(title: "Regulus: Ship beta", notes: goalNotes) == .weekGoal(projectPrefix: "Regulus", title: "Ship beta"),
      "classify should return weekGoal for goal metadata")
check(FacetAssociation.classify(title: "Regulus: Ship beta") == .item(projectPrefix: "Regulus", content: "Ship beta"),
      "classify should treat a goal-looking title as a regular item without metadata")
check(FacetAssociation.classify(title: "plain title") == .none,
      "classify should return none for unassociated title")
check(FacetAssociation.classify(title: "plain title\nRegulus: fix bug") == .none,
      "classify should ignore prefixes after the first line")

// ── ItemArrangement.sorted + ItemQuery.filteredByTag/Kind ───────────────────

let highTodo = ProjectItem(id: "high", kind: .reminder, rawTitle: "P: a",
                           projectPrefix: "P", content: "Apple", containerName: "x",
                           isCompleted: false, date: tomorrow, notes: nil, tags: ["alpha"],
                           priority: 1, url: nil)
let medTodo = ProjectItem(id: "med", kind: .reminder, rawTitle: "P: b",
                          projectPrefix: "P", content: "banana", containerName: "x",
                          isCompleted: false, date: now, notes: nil, tags: ["alpha", "beta"],
                          priority: 5, url: nil)
let noPriEvent = ProjectItem(id: "evt", kind: .event, rawTitle: "P: c",
                             projectPrefix: "P", content: "Cherry", containerName: "x",
                             isCompleted: false, date: now, notes: nil, tags: ["beta"],
                             priority: 0, url: nil)
let mixed = [medTodo, noPriEvent, highTodo]

check(ItemArrangement.sorted(mixed, by: SortOption.priorityDesc).map(\.id) == ["high", "med", "evt"],
      "priorityDesc should put highest priority first")
check(ItemArrangement.sorted(mixed, by: SortOption.nameAsc).map(\.id) == ["high", "med", "evt"],
      "nameAsc should sort by content alphabetically")
check(ItemArrangement.sorted(mixed, by: SortOption.dateAsc).first?.id != "high",
      "dateAsc should not put tomorrow's item first")
check(ItemArrangement.sorted(mixed, by: PlanSortOption.scheduleAsc, savedOrder: ["evt", "med", "high"]).map(\.id) == ["evt", "med", "high"],
      "plan schedule sort should use date first and manual order for same-time ties")
check(ItemArrangement.sorted(mixed, by: PlanSortOption.priorityDesc).map(\.id) == ["high", "med", "evt"],
      "plan priority sort should put highest priority first")
check(ItemArrangement.sorted(mixed, by: PlanSortOption.kindAsc).first?.id == "evt",
      "plan type sort should put events before reminders")

let alphaOnly = TagFilter(included: ["alpha"])
check(ItemQuery.filtered(mixed, by: alphaOnly).map(\.id).sorted() == ["high", "med"],
      "tag filter include should match items containing the tag")

let excludeBeta = TagFilter(excluded: ["beta"])
check(ItemQuery.filtered(mixed, by: excludeBeta).map(\.id) == ["high"],
      "tag filter exclude should drop items with the tag")

var cycling = TagFilter()
cycling.cycle("alpha")
check(cycling.state(of: "alpha") == .included, "first cycle should include")
cycling.cycle("alpha")
check(cycling.state(of: "alpha") == .excluded, "second cycle should exclude")
cycling.cycle("alpha")
check(cycling.state(of: "alpha") == .neutral, "third cycle should clear")
check(cycling.isEmpty, "empty include/exclude should report empty")

let bothFilters = TagFilter(included: ["alpha"], excluded: ["beta"])
check(ItemQuery.filtered(mixed, by: bothFilters).map(\.id) == ["high"],
      "include alpha and exclude beta should keep only the high-priority item")

print("FacetXCoreChecks OK")
