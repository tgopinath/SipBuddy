import XCTest
@testable import SipBuddy

final class ReminderPlannerTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    let rules = ReminderRules(intervalMinutes: 60, startMinutes: 8 * 60, endMinutes: 22 * 60,
                              activeWeekdays: Set(1...7), useWeekendHours: false,
                              weekendStartMinutes: 10 * 60, weekendEndMinutes: 20 * 60,
                              lunchEnabled: true, lunchStartMinutes: 13 * 60, lunchEndMinutes: 14 * 60,
                              sleepEnabled: true, sleepStartMinutes: 23 * 60, sleepEndMinutes: 7 * 60,
                              stopWhenGoalReached: true)

    /// 2026-11-17 is a Tuesday.
    func date(day: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: h, minute: m))!
    }

    func next(now: Date, anchor: Date?, rules: ReminderRules? = nil, goal: Bool = false,
              snooze: Date? = nil, pause: Date? = nil) -> Date? {
        ReminderPlanner.nextReminder(now: now, anchor: anchor, rules: rules ?? self.rules, goalReachedToday: goal,
                                     snoozedUntil: snooze, pausedUntil: pause, calendar: cal)
    }

    func testRegularIntervalFromLastReminder() {
        XCTAssertEqual(next(now: date(day: 17, 10, 5), anchor: date(day: 17, 10)), date(day: 17, 11))
    }

    func testDrinkingPushesNextReminderOut() {
        // Logged water at 10:40 → next reminder an interval after that.
        XCTAssertEqual(next(now: date(day: 17, 10, 41), anchor: date(day: 17, 10, 40)), date(day: 17, 11, 40))
    }

    func testNeverDuringLunch() {
        XCTAssertEqual(next(now: date(day: 17, 12, 30), anchor: date(day: 17, 12, 15)), date(day: 17, 14))
    }

    func testNeverBeforeStartOrDuringSleep() {
        // 22:30 anchor → 23:30 is sleep & after end → next day 08:00.
        XCTAssertEqual(next(now: date(day: 17, 22, 31), anchor: date(day: 17, 22, 30)), date(day: 18, 8))
    }

    func testSleepWindowWrapsMidnight() {
        var r = rules
        r.startMinutes = 0; r.endMinutes = 23 * 60 + 59
        XCTAssertFalse(ReminderPlanner.isAllowed(date(day: 17, 23, 30), rules: r, goalReachedToday: false, now: date(day: 17, 12), calendar: cal))
        XCTAssertFalse(ReminderPlanner.isAllowed(date(day: 18, 3), rules: r, goalReachedToday: false, now: date(day: 17, 12), calendar: cal))
        XCTAssertTrue(ReminderPlanner.isAllowed(date(day: 18, 7), rules: r, goalReachedToday: false, now: date(day: 17, 12), calendar: cal))
    }

    func testStopsAfterGoalAndResumesNextDay() {
        XCTAssertEqual(next(now: date(day: 17, 15), anchor: date(day: 17, 14, 30), goal: true), date(day: 18, 8))
    }

    func testGoalSettingDisabledKeepsReminding() {
        var r = rules; r.stopWhenGoalReached = false
        XCTAssertEqual(next(now: date(day: 17, 15), anchor: date(day: 17, 14, 30), rules: r, goal: true), date(day: 17, 15, 30))
    }

    func testSingleCatchUpAfterWakeInsteadOfBurst() {
        // Last reminder at 09:00, Mac slept until 15:10. Exactly one reminder, 5 min after waking.
        let n = next(now: date(day: 17, 15, 10), anchor: date(day: 17, 9))
        XCTAssertEqual(n, date(day: 17, 15, 15))
    }

    func testSnoozeOverridesInterval() {
        XCTAssertEqual(next(now: date(day: 17, 10, 0), anchor: date(day: 17, 10), snooze: date(day: 17, 10, 15)), date(day: 17, 10, 15))
    }

    func testPauseDelaysReminders() {
        XCTAssertEqual(next(now: date(day: 17, 10), anchor: date(day: 17, 10), pause: date(day: 17, 16, 20)), date(day: 17, 16, 20))
    }

    func testIndefinitePauseHasNoReminder() {
        XCTAssertNil(next(now: date(day: 17, 10), anchor: date(day: 17, 10), pause: .distantFuture))
    }

    func testWorkingDaysOnly() {
        var r = rules
        r.activeWeekdays = [2, 3, 4, 5, 6]          // Mon–Fri
        // Friday 21:30 → next allowed is Monday 08:00.
        XCTAssertEqual(next(now: date(day: 20, 21, 30), anchor: date(day: 20, 21, 30), rules: r), date(day: 23, 8))
    }

    func testWeekendHours() {
        var r = rules
        r.useWeekendHours = true
        // Saturday 07:30 → weekend start is 10:00.
        XCTAssertEqual(next(now: date(day: 21, 7, 30), anchor: nil, rules: r), date(day: 21, 10))
    }

    func testNoActiveDaysMeansNoReminder() {
        var r = rules; r.activeWeekdays = []
        XCTAssertNil(next(now: date(day: 17, 10), anchor: date(day: 17, 10), rules: r))
    }
}
