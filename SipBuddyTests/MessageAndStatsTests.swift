import XCTest
@testable import SipBuddy

final class MessageLibraryTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let name = "test-\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    func testAtLeastFiftyMessagesAcrossAllCategories() {
        XCTAssertGreaterThanOrEqual(MessageLibrary.all.count, 50)
        for c in [MessageCategory.friendly, .funny, .motivational, .caring, .workBreak, .goal] {
            XCTAssertFalse(MessageLibrary.messages(in: c).isEmpty, "\(c) is empty")
        }
    }

    func testNeverRepeatsConsecutively() {
        let lib = MessageLibrary(defaults: freshDefaults())
        let ctx = MessageContext(consumed: "1,000 ml", remaining: "1,500 ml", progress: 0.4)
        for p in Personality.allCases {
            var previous: Int?
            for _ in 0..<300 {
                _ = lib.nextMessage(personality: p, context: ctx)
                XCTAssertNotEqual(lib.lastMessageID, previous)
                previous = lib.lastMessageID
            }
        }
    }

    func testPlaceholdersAreFilled() {
        let lib = MessageLibrary(defaults: freshDefaults())
        let ctx = MessageContext(consumed: "2,000 ml", remaining: "500 ml", progress: 0.8)
        for _ in 0..<300 {
            let text = lib.nextMessage(personality: .motivationalCoach, context: ctx)
            XCTAssertFalse(text.contains("{"), text)
        }
    }

    func testMinimalPersonalityUsesMinimalMessages() {
        let lib = MessageLibrary(defaults: freshDefaults())
        let ctx = MessageContext(consumed: "0 ml", remaining: "2,500 ml", progress: 0)
        for _ in 0..<50 {
            _ = lib.nextMessage(personality: .minimalAssistant, context: ctx)
            XCTAssertEqual(MessageLibrary.all.first { $0.id == lib.lastMessageID }?.category, .minimal)
        }
    }
}

final class StatisticsTests: XCTestCase {
    let cal = Calendar.current
    func day(_ offset: Int, hour: Int = 10) -> Date {
        cal.date(byAdding: .day, value: offset, to: cal.date(bySettingHour: hour, minute: 0, second: 0, of: Date())!)!
    }

    func testTotalsStreakBestAndAverage() {
        let entries = [
            WaterEntry(amountML: 2500, date: day(-3)),
            WaterEntry(amountML: 1500, date: day(-2)), WaterEntry(amountML: 1200, date: day(-2, hour: 15)),
            WaterEntry(amountML: 3000, date: day(-1)),
            WaterEntry(amountML: 500, date: day(0)),
        ]
        let totals = StatisticsManager.dailyTotals(entries)
        XCTAssertEqual(totals[cal.startOfDay(for: day(-2))], 2700)
        // Today unfinished doesn't break the streak: -1, -2, -3 all met.
        XCTAssertEqual(StatisticsManager.streak(totals: totals, goal: 2500, today: Date()), 3)
        XCTAssertEqual(StatisticsManager.bestDay(totals: totals)?.totalML, 3000)
        let avg = StatisticsManager.averageDaily(totals: totals, days: StatisticsManager.lastDays(7, endingAt: Date()))
        XCTAssertEqual(avg, (2500 + 2700 + 3000 + 500) / 4)
    }

    func testStreakBreaksOnMissedDay() {
        let entries = [WaterEntry(amountML: 2500, date: day(-3)), WaterEntry(amountML: 2500, date: day(-1))]
        XCTAssertEqual(StatisticsManager.streak(totals: StatisticsManager.dailyTotals(entries), goal: 2500, today: Date()), 1)
    }
}

final class HydrationManagerTests: XCTestCase {
    var dir: URL!
    var settings: SettingsManager!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        settings = SettingsManager(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        settings.soundEnabled = false
    }

    func testAddUndoEditDeleteAndPersist() {
        let p = PersistenceManager(directory: dir)
        let h = HydrationManager(settings: settings, persistence: p)
        for ml in [100, 150, 250, 500] { h.add(ml) }
        XCTAssertEqual(h.todayTotal, 1000)
        XCTAssertEqual(h.remainingToday, 1000)

        h.undoLast()
        XCTAssertEqual(h.todayTotal, 500)

        var e = h.todayEntries[0]
        e.amountML = 300
        h.update(e)
        XCTAssertEqual(h.todayTotal, 700)

        h.delete(h.todayEntries[1])
        XCTAssertEqual(h.todayTotal, 550)

        // Simulates relaunching the app.
        let reloaded = HydrationManager(settings: settings, persistence: PersistenceManager(directory: dir))
        XCTAssertEqual(reloaded.todayTotal, 550)
    }

    func testResetTodayKeepsHistory() {
        let h = HydrationManager(settings: settings, persistence: PersistenceManager(directory: dir))
        h.add(400, at: Date().addingTimeInterval(-86_400 * 2))
        h.add(250)
        h.resetToday()
        XCTAssertEqual(h.todayTotal, 0)
        XCTAssertEqual(h.entries.count, 1)
    }

    func testGoalCrossingFiresOnce() {
        let h = HydrationManager(settings: settings, persistence: PersistenceManager(directory: dir))
        var fired = 0
        h.onGoalReached = { fired += 1 }
        h.add(2000); h.add(500); h.add(250)
        XCTAssertEqual(fired, 1)
        XCTAssertTrue(h.goalReachedToday)
    }

    func testCSVExport() {
        let csv = PersistenceManager.csv(for: [WaterEntry(amountML: 250, date: Date())], unit: .ounces)
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.first, "date,time,amount_ml,amount_oz")
        XCTAssertTrue(lines[1].hasSuffix(",250,8.45"))
    }

    func testUnitConversions() {
        XCTAssertEqual(VolumeUnit.liters.format(2500), "2.5 L")
        XCTAssertEqual(VolumeUnit.ounces.ml(from: 8), 237)
        XCTAssertEqual(VolumeUnit.milliliters.format(1000, symbol: false), "1,000")
    }
}
