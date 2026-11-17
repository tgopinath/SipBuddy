import Foundation

struct DaySummary: Identifiable, Equatable {
    let date: Date
    let totalML: Int
    let goalML: Int
    var id: Date { date }
    var metGoal: Bool { goalML > 0 && totalML >= goalML }
    var progress: Double { goalML > 0 ? Double(totalML) / Double(goalML) : 0 }
}

/// Pure functions over the water log.
enum StatisticsManager {
    static func dailyTotals(_ entries: [WaterEntry], calendar: Calendar = .current) -> [Date: Int] {
        var totals: [Date: Int] = [:]
        for e in entries {
            totals[calendar.startOfDay(for: e.date), default: 0] += e.amountML
        }
        return totals
    }

    static func lastDays(_ n: Int, endingAt end: Date, calendar: Calendar = .current) -> [Date] {
        let endDay = calendar.startOfDay(for: end)
        return (0..<n).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: endDay) }
    }

    static func daysInMonth(containing date: Date, calendar: Calendar = .current) -> [Date] {
        guard let interval = calendar.dateInterval(of: .month, for: date),
              let range = calendar.range(of: .day, in: .month, for: date) else { return [] }
        return range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: interval.start) }
    }

    static func summaries(for days: [Date], totals: [Date: Int], goal: Int,
                          calendar: Calendar = .current) -> [DaySummary] {
        days.map { DaySummary(date: $0, totalML: totals[calendar.startOfDay(for: $0)] ?? 0, goalML: goal) }
    }

    /// Consecutive days meeting the goal. Today counts if already met; an unfinished
    /// today doesn't break the streak.
    static func streak(totals: [Date: Int], goal: Int, today: Date, calendar: Calendar = .current) -> Int {
        guard goal > 0 else { return 0 }
        var day = calendar.startOfDay(for: today)
        if (totals[day] ?? 0) < goal {
            guard let y = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = y
        }
        var count = 0
        while (totals[day] ?? 0) >= goal {
            count += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return count
    }

    static func bestDay(totals: [Date: Int]) -> (date: Date, totalML: Int)? {
        totals.max { a, b in a.value == b.value ? a.key < b.key : a.value < b.value }
            .map { ($0.key, $0.value) }
    }

    /// Average over days in the window that have at least one entry.
    static func averageDaily(totals: [Date: Int], days: [Date], calendar: Calendar = .current) -> Int {
        let values = days.compactMap { totals[calendar.startOfDay(for: $0)] }.filter { $0 > 0 }
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / values.count
    }
}
