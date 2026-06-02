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
check(ProjectPrefix.belongs(title: "Regulus: first\nOther: second", toProject: "Regulus"),
      "belongs should match first-line project prefix")
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
check(goalTitle == "Regulus: 🎯 Ship beta", "week goal title should use project prefix and marker")
check(WeekGoalEvent.title(fromContent: "🎯 Ship beta") == "Ship beta",
      "week goal content should strip marker")
let goalNotes = WeekGoalEvent.makeNotes(body: "Focus on polish", project: "Regulus", weekID: week.id)
check(WeekGoalEvent.body(fromNotes: goalNotes) == "Focus on polish",
      "week goal notes body should hide sync marker")
check(WeekGoalEvent.hasNotesMarker(goalNotes, project: "Regulus", weekID: week.id),
      "week goal notes should include sync marker")

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
                             isCompleted: false, date: nil, notes: "needs review", priority: 0, url: nil)
check(searchItem.matches(searchQuery: ""), "empty query should match everything")
check(searchItem.matches(searchQuery: "  "), "whitespace query should match everything")
check(searchItem.matches(searchQuery: "SHIP"), "matches should be case-insensitive on content")
check(searchItem.matches(searchQuery: "review"), "matches should search notes")
check(searchItem.matches(searchQuery: "build"), "matches should search container name")
check(!searchItem.matches(searchQuery: "missing"), "non-matching query should not match")

// ── FacetAssociation ─────────────────────────────────────────────────────────

check(FacetAssociation.classify(title: "Regulus: fix bug") == .item(projectPrefix: "Regulus", content: "fix bug"),
      "classify should return item for regular title")
check(FacetAssociation.classify(title: "Regulus: 🎯 Ship beta") == .weekGoal(projectPrefix: "Regulus", title: "Ship beta"),
      "classify should return weekGoal for goal marker title")
check(FacetAssociation.classify(title: "plain title") == .none,
      "classify should return none for unassociated title")
check(FacetAssociation.classify(title: "plain title\nRegulus: fix bug") == .none,
      "classify should ignore prefixes after the first line")

print("FacetXCoreChecks OK")
