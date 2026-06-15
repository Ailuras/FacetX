import XCTest
@testable import VellumX

final class AutomationSchedulerTests: XCTestCase {
    func testDailyRunIsDueOnlyAcrossCalendarDays() {
        let calendar = utcCalendar()
        let morning = date("2026-06-07T09:00:00Z")
        let evening = date("2026-06-07T20:00:00Z")
        let tomorrow = date("2026-06-08T01:00:00Z")

        XCTAssertTrue(AutomationScheduler.needsDailyRun(lastRun: nil, now: morning, calendar: calendar))
        XCTAssertFalse(AutomationScheduler.needsDailyRun(lastRun: morning, now: evening, calendar: calendar))
        XCTAssertTrue(AutomationScheduler.needsDailyRun(lastRun: evening, now: tomorrow, calendar: calendar))
    }

    func testMonthlyRunIsDueOnlyAcrossCalendarMonths() {
        let calendar = utcCalendar()
        let earlyJune = date("2026-06-01T08:00:00Z")
        let lateJune = date("2026-06-30T23:00:00Z")
        let july = date("2026-07-01T00:00:00Z")

        XCTAssertTrue(AutomationScheduler.needsMonthlyRun(lastRun: nil, now: earlyJune, calendar: calendar))
        XCTAssertFalse(AutomationScheduler.needsMonthlyRun(lastRun: earlyJune, now: lateJune, calendar: calendar))
        XCTAssertTrue(AutomationScheduler.needsMonthlyRun(lastRun: lateJune, now: july, calendar: calendar))
    }

    // MARK: - Daily (time only)

    func testDailyBeforeScheduledTime() {
        let calendar = utcCalendar()
        let time = timeDate(hour: 14, minute: 0, calendar: calendar)
        let now = date("2026-06-07T13:30:00Z")
        XCTAssertFalse(AutomationScheduler.shouldRunAtScheduledTime(
            time: time, now: now, calendar: calendar))
    }

    func testDailyAtScheduledTime() {
        let calendar = utcCalendar()
        let time = timeDate(hour: 14, minute: 0, calendar: calendar)
        let now = date("2026-06-07T14:00:00Z")
        XCTAssertTrue(AutomationScheduler.shouldRunAtScheduledTime(
            time: time, now: now, calendar: calendar))
    }

    func testDailyAfterScheduledTime() {
        let calendar = utcCalendar()
        let time = timeDate(hour: 14, minute: 0, calendar: calendar)
        let now = date("2026-06-07T14:30:00Z")
        XCTAssertTrue(AutomationScheduler.shouldRunAtScheduledTime(
            time: time, now: now, calendar: calendar))
    }

    // MARK: - Monthly (day + time)

    func testMonthlyBeforeRequiredDay() {
        let calendar = utcCalendar()
        let time = timeDate(hour: 9, minute: 0, calendar: calendar)
        let now = date("2026-06-10T14:00:00Z")
        XCTAssertFalse(AutomationScheduler.shouldRunAtScheduledTime(
            day: 15, time: time, now: now, calendar: calendar))
    }

    func testMonthlyOnRequiredDayBeforeTime() {
        let calendar = utcCalendar()
        let time = timeDate(hour: 9, minute: 0, calendar: calendar)
        let now = date("2026-06-15T08:00:00Z")
        XCTAssertFalse(AutomationScheduler.shouldRunAtScheduledTime(
            day: 15, time: time, now: now, calendar: calendar))
    }

    func testMonthlyOnRequiredDayAtTime() {
        let calendar = utcCalendar()
        let time = timeDate(hour: 9, minute: 0, calendar: calendar)
        let now = date("2026-06-15T09:00:00Z")
        XCTAssertTrue(AutomationScheduler.shouldRunAtScheduledTime(
            day: 15, time: time, now: now, calendar: calendar))
    }

    func testMonthlyPastRequiredDayRunsImmediately() {
        let calendar = utcCalendar()
        let time = timeDate(hour: 9, minute: 0, calendar: calendar)
        let now = date("2026-06-16T06:00:00Z")
        XCTAssertTrue(AutomationScheduler.shouldRunAtScheduledTime(
            day: 15, time: time, now: now, calendar: calendar))
    }

    // MARK: - Helpers

    private func date(_ isoString: String) -> Date {
        ISO8601DateFormatter().date(from: isoString)!
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func timeDate(hour: Int, minute: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(hour: hour, minute: minute))!
    }
}
