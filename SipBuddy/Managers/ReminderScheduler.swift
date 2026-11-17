import AppKit
import Combine

/// Keeps exactly one reminder pending at a time. That design is what prevents a
/// burst of stale notifications after the Mac wakes, and it sidesteps the
/// system's 64-pending-notification limit.
final class ReminderScheduler: ObservableObject {
    @Published private(set) var nextReminderDate: Date?
    @Published private(set) var pausedUntil: Date?
    @Published private(set) var snoozedUntil: Date?

    private let settings: SettingsManager
    private let hydration: HydrationManager
    private let notifications: NotificationManager
    private let messages: MessageLibrary
    private let defaults: UserDefaults

    /// Called when a gesture-card reminder is due.
    var presentCard: ((String, String) -> Void)?

    private var lastReminderAt: Date? {
        didSet { defaults.set(lastReminderAt, forKey: "lastReminderAt") }
    }
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var activity: NSObjectProtocol?

    init(settings: SettingsManager, hydration: HydrationManager, notifications: NotificationManager,
         messages: MessageLibrary, defaults: UserDefaults = .standard) {
        self.settings = settings
        self.hydration = hydration
        self.notifications = notifications
        self.messages = messages
        self.defaults = defaults
        lastReminderAt = defaults.object(forKey: "lastReminderAt") as? Date
        pausedUntil = defaults.object(forKey: "pausedUntil") as? Date
    }

    func start() {
        settings.objectWillChange
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] in self?.reschedule() }
            .store(in: &cancellables)

        hydration.$entries
            .dropFirst()
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.reschedule() }
            .store(in: &cancellables)

        notifications.$authorizationStatus
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.reschedule() } }
            .store(in: &cancellables)

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handleWillSleep()
        }
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self?.reschedule() }
        }
        NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            self?.reschedule()
        }

        // Card reminders are driven by an in-app timer; keep App Nap from delaying it.
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "SipBuddy keeps hydration reminders on time")

        reschedule()
    }

    // MARK: - Public controls

    var isPaused: Bool { (pausedUntil ?? .distantPast) > Date() }

    var isDoneForToday: Bool {
        settings.stopWhenGoalReached && hydration.goalReachedToday
    }

    func pause(_ option: PauseOption) {
        pausedUntil = option.endDate(from: Date())
        defaults.set(pausedUntil, forKey: "pausedUntil")
        reschedule()
    }

    func resume() {
        pausedUntil = nil
        snoozedUntil = nil
        defaults.removeObject(forKey: "pausedUntil")
        reschedule()
    }

    func snooze(minutes: Int) {
        snoozedUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
        reschedule()
    }

    // MARK: - Scheduling

    func reschedule(now: Date = Date()) {
        timer?.invalidate()
        timer = nil

        if let p = pausedUntil, p <= now {
            pausedUntil = nil
            defaults.removeObject(forKey: "pausedUntil")
        }
        if let s = snoozedUntil, s <= now { snoozedUntil = nil }

        scheduleDailySummary(now: now)

        guard settings.remindersEnabled else {
            nextReminderDate = nil
            notifications.cancelReminder()
            return
        }

        let anchor = [lastReminderAt, hydration.lastEntryDate].compactMap { $0 }.max()
        let next = ReminderPlanner.nextReminder(
            now: now, anchor: anchor, rules: settings.reminderRules,
            goalReachedToday: hydration.goalReachedToday,
            snoozedUntil: snoozedUntil, pausedUntil: pausedUntil)

        nextReminderDate = next
        notifications.cancelReminder()
        guard let next else { return }

        if settings.reminderStyle == .notification {
            let msg = makeMessage()
            notifications.scheduleReminder(at: next, title: msg.title, body: msg.body)
        }

        let t = Timer(fire: next.addingTimeInterval(0.5), interval: 0, repeats: false) { [weak self] _ in
            self?.reminderDue(scheduled: next)
        }
        t.tolerance = 2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func reminderDue(scheduled: Date) {
        let now = Date()
        // A timer that fires long after its time means the Mac was asleep. Skip it;
        // the reschedule below produces one fresh catch-up reminder instead.
        let onTime = now.timeIntervalSince(scheduled) < 120
        if onTime {
            lastReminderAt = scheduled
            if settings.reminderStyle.usesGesture {
                let msg = makeMessage()
                presentCard?(msg.title, msg.body)
            }
        }
        if let s = snoozedUntil, s <= now.addingTimeInterval(1) { snoozedUntil = nil }
        reschedule(now: now.addingTimeInterval(1))
    }

    private func handleWillSleep() {
        timer?.invalidate()
        timer = nil
        notifications.cancelReminder()
    }

    func makeMessage() -> (title: String, body: String) {
        let ctx = MessageContext(
            consumed: settings.unit.format(hydration.todayTotal),
            remaining: settings.unit.format(max(0, settings.dailyGoalML - hydration.todayTotal)),
            progress: hydration.progress)
        let body = messages.nextMessage(personality: settings.personality, context: ctx)
        let title = settings.personality == .minimalAssistant ? "Hydration reminder" : "SipBuddy 💧"
        return (title, body)
    }

    private func scheduleDailySummary(now: Date) {
        guard settings.dailySummaryEnabled else {
            notifications.cancelDailySummary()
            return
        }
        let cal = Calendar.current
        var fire = Date.today(atMinutes: settings.dailySummaryMinutes)
        var isToday = true
        if fire <= now {
            fire = cal.date(byAdding: .day, value: 1, to: fire) ?? fire
            isToday = false
        }
        let goal = settings.dailyGoalML
        let total = isToday ? hydration.todayTotal : 0
        let pct = goal > 0 ? Int((Double(total) / Double(goal) * 100).rounded()) : 0
        let body: String
        if total >= goal {
            body = "You drank \(settings.unit.format(total)) today and hit your goal! 🎉 See you tomorrow."
        } else if total == 0 {
            body = "No water logged today yet. There's still time for a glass before bed. 💧"
        } else {
            body = "Today you drank \(settings.unit.format(total)) of \(settings.unit.format(goal)) (\(pct)%). Tomorrow's a fresh start! 💧"
        }
        notifications.scheduleDailySummary(at: fire, body: body)
    }
}
