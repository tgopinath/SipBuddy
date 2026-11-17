import AppKit
import SwiftUI
import Combine

/// Composition root: creates every manager once and wires them together.
final class AppModel: ObservableObject {
    let settings: SettingsManager
    let persistence: PersistenceManager
    let hydration: HydrationManager
    let notifications: NotificationManager
    let messages: MessageLibrary
    let scheduler: ReminderScheduler
    let launchAtLogin: LaunchAtLoginManager
    let menuBar: MenuBarManager
    let card: ReminderCardController
    let owner: OwnerFaceStore

    private var cancellables = Set<AnyCancellable>()

    init() {
        settings = SettingsManager()
        persistence = PersistenceManager()
        hydration = HydrationManager(settings: settings, persistence: persistence)
        notifications = NotificationManager()
        messages = MessageLibrary()
        scheduler = ReminderScheduler(settings: settings, hydration: hydration,
                                      notifications: notifications, messages: messages)
        launchAtLogin = LaunchAtLoginManager()
        menuBar = MenuBarManager()
        owner = OwnerFaceStore()
        card = ReminderCardController(settings: settings, hydration: hydration, scheduler: scheduler, owner: owner)
    }

    func start() {
        applyAppearance()
        settings.$appearance
            .sink { [weak self] _ in DispatchQueue.main.async { self?.applyAppearance() } }
            .store(in: &cancellables)
        settings.$defaultGlassML
            .sink { [weak self] ml in
                guard let self else { return }
                self.notifications.registerCategories(glassLabel: self.settings.unit.format(ml))
            }
            .store(in: &cancellables)

        notifications.onLogGlass = { [weak self] in
            guard let self else { return }
            self.hydration.add(self.settings.defaultGlassML)
        }
        notifications.onSnooze = { [weak self] minutes in self?.scheduler.snooze(minutes: minutes) }
        notifications.onOpen = { [weak self] in self?.menuBar.showPopover() }
        notifications.configure(glassLabel: settings.unit.format(settings.defaultGlassML))

        scheduler.presentCard = { [weak self] title, body in self?.card.present(title: title, message: body) }

        hydration.onGoalReached = { [weak self] in
            guard let self, !self.menuBar.isPopoverShown else { return }
            self.notifications.postNow(title: "Goal reached! 🎉",
                                       body: "You drank \(self.settings.unit.format(self.hydration.todayTotal)) today. Fantastic job taking care of yourself!")
        }

        menuBar.install(model: self)
        scheduler.start()
        card.detector.requestAccessIfNeeded()
        // Recognise the owner once, on first launch; the face is stored and reused after that.
        if !owner.isEnrolled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.card.learnOwnerOnFirstLaunch()
            }
        }
        enableLaunchAtLoginOnFirstRun()
    }

    /// SipBuddy should start with your Mac so reminders run without you opening it.
    /// Done once, only for an installed copy (so dev builds don't register login items);
    /// turning it off in Settings is respected afterwards.
    private func enableLaunchAtLoginOnFirstRun() {
        let key = "didAutoEnableLaunchAtLogin"
        guard !UserDefaults.standard.bool(forKey: key),
              Self.isInstalledCopy else { return }
        launchAtLogin.setEnabled(true)
        if launchAtLogin.isEnabled || launchAtLogin.needsApproval {
            UserDefaults.standard.set(true, forKey: key)
        }
    }

    /// True for a copy in /Applications or ~/Applications.
    static var isInstalledCopy: Bool {
        let path = Bundle.main.bundlePath
        let userApps = FileManager.default.homeDirectoryForCurrentUser.path + "/Applications/"
        return path.hasPrefix("/Applications/") || path.hasPrefix(userApps)
            || path.contains("/Users/") && path.contains("/Applications/SipBuddy.app")
    }

    private func applyAppearance() {
        NSApp.appearance = settings.appearance.nsAppearance
    }

    /// Wraps a view with every shared object plus theme modifiers.
    func inject<V: View>(_ view: V) -> some View {
        ThemedRoot(content: view)
            .environmentObject(self)
            .environmentObject(settings)
            .environmentObject(hydration)
            .environmentObject(notifications)
            .environmentObject(scheduler)
            .environmentObject(launchAtLogin)
            .environmentObject(menuBar)
            .environmentObject(card.detector)
            .environmentObject(owner)
    }
}

/// Re-applies the accent colour whenever it changes.
private struct ThemedRoot<Content: View>: View {
    @EnvironmentObject var settings: SettingsManager
    let content: Content
    var body: some View {
        content.tint(settings.accent.color)
    }
}
