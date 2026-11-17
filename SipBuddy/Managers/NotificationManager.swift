import Foundation
import UserNotifications

/// Wraps UNUserNotificationCenter: permission, categories with quick actions,
/// and the single pending reminder.
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let reminderID = "sipbuddy.reminder"
    static let summaryID = "sipbuddy.dailySummary"
    static let reminderCategory = "SIPBUDDY_REMINDER"
    static let logAction = "LOG_GLASS"
    static let snooze15Action = "SNOOZE_15"
    static let snooze30Action = "SNOOZE_30"

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    var onLogGlass: (() -> Void)?
    var onSnooze: ((Int) -> Void)?
    var onOpen: (() -> Void)?

    private let center = UNUserNotificationCenter.current()

    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional
    }

    func configure(glassLabel: String) {
        center.delegate = self
        registerCategories(glassLabel: glassLabel)
        refreshStatus { [weak self] status in
            if status == .notDetermined { self?.requestAuthorization() }
        }
    }

    func registerCategories(glassLabel: String) {
        let log = UNNotificationAction(identifier: Self.logAction, title: "💧 Log \(glassLabel)", options: [])
        let s15 = UNNotificationAction(identifier: Self.snooze15Action, title: "Snooze 15 min", options: [])
        let s30 = UNNotificationAction(identifier: Self.snooze30Action, title: "Snooze 30 min", options: [])
        let category = UNNotificationCategory(identifier: Self.reminderCategory, actions: [log, s15, s30],
                                              intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }

    func refreshStatus(_ completion: ((UNAuthorizationStatus) -> Void)? = nil) {
        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.authorizationStatus = settings.authorizationStatus
                completion?(settings.authorizationStatus)
            }
        }
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, error in
            if let error { NSLog("SipBuddy: notification permission error: \(error.localizedDescription)") }
            self.refreshStatus()
        }
    }

    // MARK: - Scheduling

    func scheduleReminder(at date: Date, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Self.reminderCategory
        content.threadIdentifier = "sipbuddy"
        add(id: Self.reminderID, content: content, at: date)
    }

    func cancelReminder() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.reminderID])
    }

    func scheduleDailySummary(at date: Date, body: String) {
        let content = UNMutableNotificationContent()
        content.title = "Your hydration today"
        content.body = body
        content.sound = .default
        content.threadIdentifier = "sipbuddy"
        add(id: Self.summaryID, content: content, at: date)
    }

    func cancelDailySummary() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.summaryID])
    }

    func postNow(title: String, body: String, id: String = UUID().uuidString) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Self.reminderCategory
        content.threadIdentifier = "sipbuddy"
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    private func add(id: String, content: UNNotificationContent, at date: Date) {
        let interval = max(1, date.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        // Re-using the identifier replaces any pending request, so there is never more than one.
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger)) { error in
            if let error { NSLog("SipBuddy: failed to schedule \(id): \(error.localizedDescription)") }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        DispatchQueue.main.async {
            switch action {
            case Self.logAction: self.onLogGlass?()
            case Self.snooze15Action: self.onSnooze?(15)
            case Self.snooze30Action: self.onSnooze?(30)
            case UNNotificationDefaultActionIdentifier: self.onOpen?()
            default: break
            }
            completionHandler()
        }
    }
}
