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

print("FacetXCoreChecks OK")
