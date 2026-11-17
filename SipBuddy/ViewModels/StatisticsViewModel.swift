import Foundation

enum StatsRange: String, CaseIterable, Identifiable {
    case week = "Week", month = "Month"
    var id: String { rawValue }
}

/// Everything the statistics screen shows, computed once per render from the log.
struct StatisticsViewModel {
    let goal: Int
    let totals: [Date: Int]
    let todayTotal: Int
    let glassesToday: Int
    let streak: Int
    let average30: Int
    let best: (date: Date, totalML: Int)?
    let chartDays: [DaySummary]

    init(entries: [WaterEntry], goal: Int, range: StatsRange, monthAnchor: Date, now: Date = Date(),
         calendar: Calendar = .current) {
        self.goal = goal
        totals = StatisticsManager.dailyTotals(entries, calendar: calendar)
        todayTotal = totals[calendar.startOfDay(for: now)] ?? 0
        glassesToday = entries.filter { calendar.isDate($0.date, inSameDayAs: now) }.count
        streak = StatisticsManager.streak(totals: totals, goal: goal, today: now, calendar: calendar)
        average30 = StatisticsManager.averageDaily(totals: totals,
                                                   days: StatisticsManager.lastDays(30, endingAt: now, calendar: calendar),
                                                   calendar: calendar)
        best = StatisticsManager.bestDay(totals: totals)
        let days: [Date]
        switch range {
        case .week: days = StatisticsManager.lastDays(7, endingAt: now, calendar: calendar)
        case .month: days = StatisticsManager.daysInMonth(containing: monthAnchor, calendar: calendar)
        }
        chartDays = StatisticsManager.summaries(for: days, totals: totals, goal: goal, calendar: calendar)
    }

    var todayPercent: Int { goal > 0 ? Int((Double(todayTotal) / Double(goal) * 100).rounded()) : 0 }
    var daysMetInRange: Int { chartDays.filter(\.metGoal).count }
    var rangeTotal: Int { chartDays.reduce(0) { $0 + $1.totalML } }
}
