import Foundation

/// A snapshot of the reminder settings, so planning stays a pure function.
struct ReminderRules: Equatable {
    var intervalMinutes: Int
    var startMinutes: Int
    var endMinutes: Int
    var activeWeekdays: Set<Int>          // Calendar weekday: 1 = Sunday … 7 = Saturday
    var useWeekendHours: Bool
    var weekendStartMinutes: Int
    var weekendEndMinutes: Int
    var lunchEnabled: Bool
    var lunchStartMinutes: Int
    var lunchEndMinutes: Int
    var sleepEnabled: Bool
    var sleepStartMinutes: Int
    var sleepEndMinutes: Int
    var stopWhenGoalReached: Bool
}

/// Decides when the next reminder may fire. No side effects — fully unit tested.
enum ReminderPlanner {
    /// When the last reminder or drink is older than one interval (Mac was asleep,
    /// app was closed), we send a single catch-up reminder this long after "now"
    /// instead of a burst of missed ones.
    static let catchUpDelay: TimeInterval = 5 * 60

    static func isAllowed(_ date: Date, rules: ReminderRules, goalReachedToday: Bool,
                          now: Date, calendar: Calendar = .current) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        guard rules.activeWeekdays.contains(weekday) else { return false }

        let m = date.minutesOfDay(calendar)
        let isWeekend = weekday == 1 || weekday == 7
        let start = (rules.useWeekendHours && isWeekend) ? rules.weekendStartMinutes : rules.startMinutes
        let end = (rules.useWeekendHours && isWeekend) ? rules.weekendEndMinutes : rules.endMinutes
        guard inWindow(m, start: start, end: end, endInclusive: true) else { return false }

        if rules.lunchEnabled, inWindow(m, start: rules.lunchStartMinutes, end: rules.lunchEndMinutes, endInclusive: false) {
            return false
        }
        if rules.sleepEnabled, inWindow(m, start: rules.sleepStartMinutes, end: rules.sleepEndMinutes, endInclusive: false) {
            return false
        }
        if rules.stopWhenGoalReached, goalReachedToday, calendar.isDate(date, inSameDayAs: now) {
            return false
        }
        return true
    }

    /// Handles windows that wrap past midnight (e.g. sleep 23:00 → 07:00).
    static func inWindow(_ m: Int, start: Int, end: Int, endInclusive: Bool) -> Bool {
        if start == end { return endInclusive && m == start }
        if start < end {
            return m >= start && (endInclusive ? m <= end : m < end)
        }
        return m >= start || (endInclusive ? m <= end : m < end)
    }

    /// The earliest moment the next reminder could fire, before applying quiet hours.
    /// Returns nil when reminders are paused indefinitely.
    static func earliestCandidate(now: Date, anchor: Date?, rules: ReminderRules,
                                  snoozedUntil: Date?, pausedUntil: Date?) -> Date? {
        if let paused = pausedUntil, paused == .distantFuture { return nil }

        var candidate: Date
        if let snooze = snoozedUntil, snooze > now {
            candidate = snooze
        } else {
            let interval = TimeInterval(rules.intervalMinutes * 60)
            candidate = (anchor ?? now).addingTimeInterval(interval)
            if candidate <= now {
                candidate = now.addingTimeInterval(min(interval, catchUpDelay))
            }
        }
        if let paused = pausedUntil, paused > candidate { candidate = paused }
        return candidate
    }

    /// Walks forward minute by minute (cheap: max ~11k checks) to the first allowed time.
    static func nextAllowedDate(from earliest: Date, rules: ReminderRules, goalReachedToday: Bool,
                                now: Date, calendar: Calendar = .current) -> Date? {
        var t = earliest
        let seconds = calendar.component(.second, from: t)
        if seconds > 0 { t = t.addingTimeInterval(TimeInterval(60 - seconds)) }
        let limit = 8 * 24 * 60
        for _ in 0..<limit {
            if isAllowed(t, rules: rules, goalReachedToday: goalReachedToday, now: now, calendar: calendar) {
                return t
            }
            t = t.addingTimeInterval(60)
        }
        return nil
    }

    static func nextReminder(now: Date, anchor: Date?, rules: ReminderRules, goalReachedToday: Bool,
                             snoozedUntil: Date?, pausedUntil: Date?, calendar: Calendar = .current) -> Date? {
        guard let earliest = earliestCandidate(now: now, anchor: anchor, rules: rules,
                                               snoozedUntil: snoozedUntil, pausedUntil: pausedUntil) else { return nil }
        return nextAllowedDate(from: earliest, rules: rules, goalReachedToday: goalReachedToday,
                               now: now, calendar: calendar)
    }
}
