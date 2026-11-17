import AppKit
import SwiftUI
import Combine
import AVFoundation

/// State shown on the reminder.
final class ReminderCardModel: ObservableObject {
    @Published var title = ""
    @Published var message = ""
    @Published var loggedAmount: String?
    @Published var isVisible = false
    @Published var dismissing = false
}

/// Shows reminders that stay put until the camera sees you drinking
/// (or, in relaxed mode, they're closed). Full-screen mode covers every
/// connected display; the one with the camera gets the camera view.
final class ReminderCardController {
    let model = ReminderCardModel()
    let detector: DrinkingDetector

    private let settings: SettingsManager
    private let hydration: HydrationManager
    private weak var scheduler: ReminderScheduler?
    private var panels: [NSPanel] = []
    private var cancellables = Set<AnyCancellable>()

    init(settings: SettingsManager, hydration: HydrationManager, scheduler: ReminderScheduler, owner: OwnerFaceStore) {
        self.detector = DrinkingDetector(owner: owner)
        self.settings = settings
        self.hydration = hydration
        self.scheduler = scheduler
        detector.onDrinking = { [weak self] in self?.dismiss(byDrinking: true) }
        detector.prepare()
        detector.onLearningFinished = { [weak self] in
            guard let self else { return }
            if self.isOnboarding {
                // First-launch welcome: say thanks and close.
                self.isOnboarding = false
                self.model.message = "Got it! I'll recognise you from now on. 🙂"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.dismiss(byDrinking: false) }
            } else if !self.isShowing {
                // Learned from Settings with no reminder up: turn the camera back off.
                self.detector.stop()
            }
        }

        // If the user switches to standard notifications, don't leave a reminder behind.
        settings.$reminderStyle
            .sink { [weak self] style in
                if style == .notification { self?.dismiss(byDrinking: false) }
            }
            .store(in: &cancellables)

        // Monitors plugged in or removed while a reminder is up: re-cover all screens.
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            guard let self, self.isShowing, self.settings.reminderStyle == .fullScreen else { return }
            self.buildPanels(fullScreen: true)
        }
    }

    var isShowing: Bool { panels.contains { $0.isVisible } }

    private var isOnboarding = false

    /// First launch only: learn the owner's face once and store it.
    func learnOwnerOnFirstLaunch() {
        guard !detector.owner.isEnrolled, !isShowing else { return }
        isOnboarding = true
        present(title: "Welcome to SipBuddy 👋",
                message: "Look at the camera for a few seconds so I can recognise you. I'll only do this once.",
                session: true)
        detector.startLearning()
    }

    /// "Drink now": a corner card that counts every sip and logs them when you stop.
    func startDrinkSession() {
        present(title: "Drink now 💧", message: "Drink up — I'll count each swallow and log the water.", session: true)
    }

    func present(title: String, message: String, session: Bool = false) {
        // Ask for the camera first, so the system dialog isn't hidden behind the reminder.
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { _ in
                DispatchQueue.main.async { self.present(title: title, message: message, session: session) }
            }
            return
        }
        model.title = title
        model.message = message
        model.loggedAmount = nil
        model.dismissing = false

        buildPanels(fullScreen: !session && settings.reminderStyle == .fullScreen)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { model.isVisible = true }
        if settings.soundEnabled && !session { NSSound(named: "Purr")?.play() }
        detector.start(session: session)
    }

    /// Estimated water from the sips counted so far.
    var estimatedML: Int { detector.sipCount * settings.mlPerSip }

    func snooze(minutes: Int) {
        scheduler?.snooze(minutes: minutes)
        dismiss(byDrinking: false)
    }

    func dismiss(byDrinking: Bool) {
        guard isShowing else { return }
        // Log what the camera counted, however the reminder was closed. No manual entry.
        let ml = estimatedML
        if ml > 0 {
            hydration.add(ml, announce: false)
            model.loggedAmount = "\(settings.unit.format(ml)) (\(detector.sipCount) swallows)"
        } else {
            model.loggedAmount = nil
        }
        detector.cancelLearning()
        detector.stop()
        if byDrinking, settings.soundEnabled { NSSound(named: "Tink")?.play() }
        model.dismissing = byDrinking && ml > 0
        let closing = panels
        let delay = byDrinking ? 0.9 : 0.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.easeIn(duration: 0.2)) { self.model.isVisible = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                closing.forEach { $0.orderOut(nil) }
                self.model.dismissing = false
            }
        }
    }

    func retryCamera() { detector.start() }

    // MARK: - Panels

    private func buildPanels(fullScreen: Bool) {
        panels.forEach { $0.orderOut(nil) }
        panels = []

        if fullScreen {
            let cameraScreen = Self.cameraScreen()
            for screen in NSScreen.screens {
                let panel = makeFullScreenPanel(isCameraScreen: screen == cameraScreen)
                panel.setFrame(screen.frame, display: true)
                panel.orderFrontRegardless()
                panels.append(panel)
            }
        } else {
            let panel = makeCornerPanel()
            if let frame = Self.screenUnderMouse()?.visibleFrame {
                panel.setFrameOrigin(NSPoint(x: frame.maxX - panel.frame.width - 12,
                                             y: frame.maxY - panel.frame.height - 8))
            }
            panel.orderFrontRegardless()
            panels.append(panel)
        }
    }

    private func basePanel(level: NSWindow.Level) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = level
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        return panel
    }

    private func makeFullScreenPanel(isCameraScreen: Bool) -> NSPanel {
        // Above the menu bar and Dock, like a screen saver.
        let panel = basePanel(level: .screenSaver)
        let hosting = NSHostingView(rootView: FullScreenReminderView(controller: self, isCameraScreen: isCameraScreen)
            .environmentObject(model).environmentObject(detector)
            .environmentObject(settings).environmentObject(hydration))
        // Blur whatever is behind the reminder.
        let blur = NSVisualEffectView()
        blur.material = .fullScreenUI
        blur.blendingMode = .behindWindow
        blur.state = .active
        panel.contentView = blur
        hosting.frame = blur.bounds
        hosting.autoresizingMask = [.width, .height]
        blur.addSubview(hosting)
        return panel
    }

    private func makeCornerPanel() -> NSPanel {
        let panel = basePanel(level: .statusBar)
        panel.isMovableByWindowBackground = true
        let hosting = NSHostingView(rootView: ReminderCardView(controller: self)
            .environmentObject(model).environmentObject(detector).environmentObject(settings))
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        panel.setContentSize(NSSize(width: 400, height: 300))
        return panel
    }

    // MARK: - Screens

    /// The display you face while drinking: the built-in screen when the
    /// built-in camera is in use, otherwise the main screen.
    static func cameraScreen() -> NSScreen? {
        let device = AVCaptureDevice.default(for: .video)
        if device?.deviceType == .builtInWideAngleCamera,
           let builtIn = NSScreen.screens.first(where: { CGDisplayIsBuiltin($0.displayID) != 0 }) {
            return builtIn
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    static func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
