import Foundation
import Combine

/// All user preferences, persisted to UserDefaults. Every change publishes, so the
/// scheduler and UI react immediately.
final class SettingsManager: ObservableObject {
    static let intervalPresets = [30, 45, 60, 90, 120]
    static let glassPresets = [100, 150, 200, 250, 300, 330, 400, 500]

    private let defaults: UserDefaults

    // Hydration
    @Published var dailyGoalML: Int { didSet { defaults.set(dailyGoalML, forKey: K.goal) } }
    @Published var defaultGlassML: Int { didSet { defaults.set(defaultGlassML, forKey: K.glass) } }
    /// Estimated water per counted sip; an average adult swallow is about 20–30 ml.
    @Published var mlPerSip: Int { didSet { defaults.set(mlPerSip, forKey: K.mlPerSip) } }
    @Published var unit: VolumeUnit { didSet { defaults.set(unit.rawValue, forKey: K.unit) } }
    @Published var soundEnabled: Bool { didSet { defaults.set(soundEnabled, forKey: K.sound) } }
    @Published var dailySummaryEnabled: Bool { didSet { defaults.set(dailySummaryEnabled, forKey: K.summary) } }
    @Published var dailySummaryMinutes: Int { didSet { defaults.set(dailySummaryMinutes, forKey: K.summaryTime) } }

    // Reminders
    @Published var remindersEnabled: Bool { didSet { defaults.set(remindersEnabled, forKey: K.enabled) } }
    @Published var reminderStyle: ReminderStyle { didSet { defaults.set(reminderStyle.rawValue, forKey: K.style) } }
    @Published var gestureOnlyDismiss: Bool { didSet { defaults.set(gestureOnlyDismiss, forKey: K.gestureOnly) } }
    @Published var showCameraPreview: Bool { didSet { defaults.set(showCameraPreview, forKey: K.preview) } }
    @Published var intervalMinutes: Int { didSet { defaults.set(intervalMinutes, forKey: K.interval) } }
    @Published var startMinutes: Int { didSet { defaults.set(startMinutes, forKey: K.start) } }
    @Published var endMinutes: Int { didSet { defaults.set(endMinutes, forKey: K.end) } }
    @Published var activeWeekdays: Set<Int> { didSet { defaults.set(Array(activeWeekdays).sorted(), forKey: K.weekdays) } }
    @Published var useWeekendHours: Bool { didSet { defaults.set(useWeekendHours, forKey: K.weekendHours) } }
    @Published var weekendStartMinutes: Int { didSet { defaults.set(weekendStartMinutes, forKey: K.weekendStart) } }
    @Published var weekendEndMinutes: Int { didSet { defaults.set(weekendEndMinutes, forKey: K.weekendEnd) } }
    @Published var lunchEnabled: Bool { didSet { defaults.set(lunchEnabled, forKey: K.lunch) } }
    @Published var lunchStartMinutes: Int { didSet { defaults.set(lunchStartMinutes, forKey: K.lunchStart) } }
    @Published var lunchEndMinutes: Int { didSet { defaults.set(lunchEndMinutes, forKey: K.lunchEnd) } }
    @Published var sleepEnabled: Bool { didSet { defaults.set(sleepEnabled, forKey: K.sleep) } }
    @Published var sleepStartMinutes: Int { didSet { defaults.set(sleepStartMinutes, forKey: K.sleepStart) } }
    @Published var sleepEndMinutes: Int { didSet { defaults.set(sleepEndMinutes, forKey: K.sleepEnd) } }
    @Published var stopWhenGoalReached: Bool { didSet { defaults.set(stopWhenGoalReached, forKey: K.stopAtGoal) } }

    // Personality
    @Published var personality: Personality { didSet { defaults.set(personality.rawValue, forKey: K.personality) } }
    @Published var showGreetings: Bool { didSet { defaults.set(showGreetings, forKey: K.greetings) } }

    // Appearance
    @Published var appearance: AppearanceMode { didSet { defaults.set(appearance.rawValue, forKey: K.appearance) } }
    @Published var accent: AccentChoice { didSet { defaults.set(accent.rawValue, forKey: K.accent) } }

    // General
    @Published var showMenuBarIcon: Bool { didSet { defaults.set(showMenuBarIcon, forKey: K.menuIcon) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func int(_ k: String, _ d: Int) -> Int { defaults.object(forKey: k) as? Int ?? d }
        func bool(_ k: String, _ d: Bool) -> Bool { defaults.object(forKey: k) as? Bool ?? d }
        func str(_ k: String) -> String { defaults.string(forKey: k) ?? "" }

        dailyGoalML = int(K.goal, 2000)
        defaultGlassML = int(K.glass, 250)
        mlPerSip = int(K.mlPerSip, 25)
        unit = VolumeUnit(rawValue: str(K.unit)) ?? .milliliters
        soundEnabled = bool(K.sound, true)
        dailySummaryEnabled = bool(K.summary, true)
        dailySummaryMinutes = int(K.summaryTime, 21 * 60)

        remindersEnabled = bool(K.enabled, true)
        reminderStyle = ReminderStyle(rawValue: str(K.style)) ?? .fullScreen
        gestureOnlyDismiss = bool(K.gestureOnly, true)
        showCameraPreview = bool(K.preview, true)
        intervalMinutes = int(K.interval, 60)
        startMinutes = int(K.start, 8 * 60)
        endMinutes = int(K.end, 22 * 60)
        activeWeekdays = Set((defaults.array(forKey: K.weekdays) as? [Int]) ?? Array(1...7))
        useWeekendHours = bool(K.weekendHours, false)
        weekendStartMinutes = int(K.weekendStart, 9 * 60)
        weekendEndMinutes = int(K.weekendEnd, 22 * 60)
        lunchEnabled = bool(K.lunch, false)
        lunchStartMinutes = int(K.lunchStart, 13 * 60)
        lunchEndMinutes = int(K.lunchEnd, 14 * 60)
        sleepEnabled = bool(K.sleep, true)
        sleepStartMinutes = int(K.sleepStart, 23 * 60)
        sleepEndMinutes = int(K.sleepEnd, 7 * 60)
        stopWhenGoalReached = bool(K.stopAtGoal, true)

        personality = Personality(rawValue: str(K.personality)) ?? .friendlyFriend
        showGreetings = bool(K.greetings, true)

        appearance = AppearanceMode(rawValue: str(K.appearance)) ?? .system
        accent = AccentChoice(rawValue: str(K.accent)) ?? .ocean

        showMenuBarIcon = bool(K.menuIcon, true)
    }

    var reminderRules: ReminderRules {
        ReminderRules(
            intervalMinutes: max(5, intervalMinutes),
            startMinutes: startMinutes, endMinutes: endMinutes,
            activeWeekdays: activeWeekdays,
            useWeekendHours: useWeekendHours,
            weekendStartMinutes: weekendStartMinutes, weekendEndMinutes: weekendEndMinutes,
            lunchEnabled: lunchEnabled, lunchStartMinutes: lunchStartMinutes, lunchEndMinutes: lunchEndMinutes,
            sleepEnabled: sleepEnabled, sleepStartMinutes: sleepStartMinutes, sleepEndMinutes: sleepEndMinutes,
            stopWhenGoalReached: stopWhenGoalReached
        )
    }

    private enum K {
        static let goal = "dailyGoalML", glass = "defaultGlassML", mlPerSip = "mlPerSip", unit = "unit", sound = "soundEnabled"
        static let summary = "dailySummaryEnabled", summaryTime = "dailySummaryMinutes"
        static let enabled = "remindersEnabled", style = "reminderStyle", gestureOnly = "gestureOnlyDismiss"
        static let preview = "showCameraPreview", interval = "intervalMinutes"
        static let start = "startMinutes", end = "endMinutes", weekdays = "activeWeekdays"
        static let weekendHours = "useWeekendHours", weekendStart = "weekendStartMinutes", weekendEnd = "weekendEndMinutes"
        static let lunch = "lunchEnabled", lunchStart = "lunchStartMinutes", lunchEnd = "lunchEndMinutes"
        static let sleep = "sleepEnabled", sleepStart = "sleepStartMinutes", sleepEnd = "sleepEndMinutes"
        static let stopAtGoal = "stopWhenGoalReached", personality = "personality", greetings = "showGreetings"
        static let appearance = "appearance", accent = "accent", menuIcon = "showMenuBarIcon"
    }
}
