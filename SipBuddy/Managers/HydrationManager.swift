import AppKit
import Combine

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    var canUndo: Bool = false
}

/// Owns the water log: adding, undoing, editing and deleting entries.
/// History is never cleared at midnight; "today" is just a filter on the date.
final class HydrationManager: ObservableObject {
    @Published private(set) var entries: [WaterEntry] = []
    @Published private(set) var today: Date = Calendar.current.startOfDay(for: Date())
    @Published var toast: Toast?
    @Published var celebrate = false
    @Published var lastSaveError: String?

    private let settings: SettingsManager
    private let persistence: PersistenceManager
    private var lastAddedID: UUID?
    private var toastWork: DispatchWorkItem?
    private var dayTimer: Timer?

    /// Fired when today's total crosses the goal.
    var onGoalReached: (() -> Void)?

    init(settings: SettingsManager, persistence: PersistenceManager) {
        self.settings = settings
        self.persistence = persistence
        entries = persistence.loadEntries()

        NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            self?.refreshDay()
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refreshDay()
        }
        // Belt and braces: the day-changed notification can be missed while asleep.
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.refreshDay() }
        t.tolerance = 10
        RunLoop.main.add(t, forMode: .common)
        dayTimer = t
    }

    // MARK: - Derived values

    var calendar: Calendar { .current }

    func entries(on day: Date) -> [WaterEntry] {
        entries.filter { calendar.isDate($0.date, inSameDayAs: day) }
    }

    func total(on day: Date) -> Int {
        entries(on: day).reduce(0) { $0 + $1.amountML }
    }

    var todayEntries: [WaterEntry] { entries(on: Date()) }
    var todayTotal: Int { total(on: Date()) }
    var remainingToday: Int { max(0, settings.dailyGoalML - todayTotal) }
    var goalReachedToday: Bool { todayTotal >= settings.dailyGoalML }
    var lastEntryDate: Date? { entries.last?.date }

    var progress: Double {
        guard settings.dailyGoalML > 0 else { return 0 }
        return Double(todayTotal) / Double(settings.dailyGoalML)
    }

    var glassesToday: Int { todayEntries.count }

    // MARK: - Mutations

    func add(_ ml: Int, at date: Date = Date(), announce: Bool = true) {
        guard ml > 0 else { return }
        let wasReached = goalReachedToday
        let entry = WaterEntry(amountML: ml, date: date)
        entries.append(entry)
        entries.sort { $0.date < $1.date }
        lastAddedID = entry.id
        save()

        if settings.soundEnabled { NSSound(named: "Pop")?.play() }

        if !wasReached && goalReachedToday && calendar.isDateInToday(date) {
            showToast(Toast(text: "🎉 You reached today's goal! Amazing work.", canUndo: true))
            celebrate = true
            if settings.soundEnabled {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSSound(named: "Glass")?.play() }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in self?.celebrate = false }
            onGoalReached?()
        } else if announce {
            showToast(Toast(text: "Great! You just added \(settings.unit.format(ml)). 💧", canUndo: true))
        }
    }

    func undoLast() {
        let target: WaterEntry?
        if let id = lastAddedID, let e = entries.first(where: { $0.id == id }) {
            target = e
        } else {
            target = todayEntries.last
        }
        guard let entry = target else { return }
        entries.removeAll { $0.id == entry.id }
        lastAddedID = nil
        save()
        showToast(Toast(text: "Removed \(settings.unit.format(entry.amountML))."))
    }

    func update(_ entry: WaterEntry) {
        guard let i = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[i] = entry
        entries.sort { $0.date < $1.date }
        save()
    }

    func delete(_ entry: WaterEntry) {
        entries.removeAll { $0.id == entry.id }
        if lastAddedID == entry.id { lastAddedID = nil }
        save()
    }

    /// Clears today's entries only. Past days stay untouched.
    func resetToday() {
        entries.removeAll { calendar.isDateInToday($0.date) }
        lastAddedID = nil
        save()
        showToast(Toast(text: "Today's progress was reset."))
    }

    func showToast(_ toast: Toast) {
        toastWork?.cancel()
        self.toast = toast
        let work = DispatchWorkItem { [weak self] in
            if self?.toast?.id == toast.id { self?.toast = nil }
        }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    // MARK: - Private

    private func refreshDay() {
        let start = calendar.startOfDay(for: Date())
        if start != today { today = start }
    }

    private func save() {
        do {
            try persistence.save(entries)
            lastSaveError = nil
        } catch {
            lastSaveError = "Couldn't save your history: \(error.localizedDescription)"
            NSLog("SipBuddy: \(lastSaveError!)")
        }
    }
}
