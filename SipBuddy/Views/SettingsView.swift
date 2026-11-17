import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct SettingsView: View {
    var body: some View {
        TabView {
            HydrationSettings().tabItem { Label("Hydration", systemImage: "drop") }
            ReminderSettings().tabItem { Label("Reminders", systemImage: "bell") }
            PersonalitySettings().tabItem { Label("Personality", systemImage: "face.smiling") }
            AppearanceSettings().tabItem { Label("Appearance", systemImage: "paintpalette") }
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
        }
        .padding(.top, 28)
        .frame(width: 600, height: 560)
    }
}

/// Binds a "minutes after midnight" setting to a time picker.
private func timeBinding(_ settings: SettingsManager, _ keyPath: ReferenceWritableKeyPath<SettingsManager, Int>) -> Binding<Date> {
    Binding(get: { Date.today(atMinutes: settings[keyPath: keyPath]) },
            set: { settings[keyPath: keyPath] = $0.minutesOfDay() })
}

// MARK: - Hydration

private struct HydrationSettings: View {
    @EnvironmentObject var settings: SettingsManager

    var body: some View {
        Form {
            FaceSection()

            Section("Daily goal") {
                LabeledContent("Daily water target") {
                    HStack {
                        Text(settings.unit.format(settings.dailyGoalML))
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .frame(minWidth: 70, alignment: .trailing)
                        Stepper("", value: $settings.dailyGoalML, in: 500...6000, step: 100)
                            .labelsHidden()
                    }
                }
                Slider(value: Binding(get: { Double(settings.dailyGoalML) },
                                      set: { settings.dailyGoalML = Int(($0 / 50).rounded()) * 50 }),
                       in: 1000...5000) {
                    EmptyView()
                } minimumValueLabel: {
                    Text(settings.unit.format(1000)).font(.caption)
                } maximumValueLabel: {
                    Text(settings.unit.format(5000)).font(.caption)
                }
                Stepper("Water per swallow: \(settings.unit.format(settings.mlPerSip))",
                        value: $settings.mlPerSip, in: 10...60, step: 5)
                Picker("Default glass size", selection: $settings.defaultGlassML) {
                    ForEach(SettingsManager.glassPresets, id: \.self) { Text(settings.unit.format($0)).tag($0) }
                }
                Picker("Units", selection: $settings.unit) {
                    ForEach(VolumeUnit.allCases) { Text($0.label).tag($0) }
                }
            }
            Section("Feedback") {
                Toggle("Play a gentle sound when logging water", isOn: $settings.soundEnabled)
                Toggle("Daily summary notification", isOn: $settings.dailySummaryEnabled)
                if settings.dailySummaryEnabled {
                    DatePicker("Summary time", selection: timeBinding(settings, \.dailySummaryMinutes),
                               displayedComponents: .hourAndMinute)
                }
            }
            Section {
                Text("SipBuddy is a friendly reminder, not medical advice. Your ideal intake depends on you — a health professional can help you choose a target.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Reminders

private struct ReminderSettings: View {
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var notifications: NotificationManager
    @EnvironmentObject var scheduler: ReminderScheduler

    @State private var customInterval = false
    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        Form {
            Section {
                Toggle("Enable reminders", isOn: $settings.remindersEnabled)
                Picker("Reminder style", selection: $settings.reminderStyle) {
                    ForEach(ReminderStyle.allCases) { Text($0.label).tag($0) }
                }
                if settings.reminderStyle.usesGesture {
                    Toggle("Hide the Snooze button on reminders", isOn: $settings.gestureOnlyDismiss)
                    Toggle("Show camera preview on the card", isOn: $settings.showCameraPreview)
                    cameraRow
                    Text("The reminder stays on screen until the camera counts 5 swallows while you drink from a bottle or cup, or you click ✕. The camera runs only while a reminder is showing, pauses after 10 minutes, and nothing is recorded. Only the person closest to the camera counts.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    permissionRow
                }
                if scheduler.isPaused {
                    LabeledContent("Status") {
                        HStack {
                            Text("Paused").foregroundStyle(.orange)
                            Button("Resume") { scheduler.resume() }
                        }
                    }
                } else {
                    Picker("Pause reminders", selection: Binding<PauseOption?>(get: { nil }, set: { if let o = $0 { scheduler.pause(o) } })) {
                        Text("Choose…").tag(PauseOption?.none)
                        ForEach(PauseOption.allCases) { Text($0.label).tag(PauseOption?.some($0)) }
                    }
                }
            }

            Section("Schedule") {
                Picker("Remind me every", selection: Binding(
                    get: { customInterval || !SettingsManager.intervalPresets.contains(settings.intervalMinutes) ? -1 : settings.intervalMinutes },
                    set: { value in
                        if value == -1 { customInterval = true } else { customInterval = false; settings.intervalMinutes = value }
                    })) {
                    ForEach(SettingsManager.intervalPresets, id: \.self) { Text("\($0) minutes").tag($0) }
                    Text("Custom…").tag(-1)
                }
                if customInterval || !SettingsManager.intervalPresets.contains(settings.intervalMinutes) {
                    Stepper("Custom interval: \(settings.intervalMinutes) minutes", value: $settings.intervalMinutes, in: 10...240, step: 5)
                }
                DatePicker("Start time", selection: timeBinding(settings, \.startMinutes), displayedComponents: .hourAndMinute)
                DatePicker("End time", selection: timeBinding(settings, \.endMinutes), displayedComponents: .hourAndMinute)
                LabeledContent("Reminder days") { WeekdayPicker(selection: $settings.activeWeekdays) }
                Toggle("Different hours on weekends", isOn: $settings.useWeekendHours)
                if settings.useWeekendHours {
                    DatePicker("Weekend start", selection: timeBinding(settings, \.weekendStartMinutes), displayedComponents: .hourAndMinute)
                    DatePicker("Weekend end", selection: timeBinding(settings, \.weekendEndMinutes), displayedComponents: .hourAndMinute)
                }
            }

            Section("Quiet times") {
                Toggle("Lunch break", isOn: $settings.lunchEnabled)
                if settings.lunchEnabled {
                    DatePicker("Lunch from", selection: timeBinding(settings, \.lunchStartMinutes), displayedComponents: .hourAndMinute)
                    DatePicker("Lunch until", selection: timeBinding(settings, \.lunchEndMinutes), displayedComponents: .hourAndMinute)
                }
                Toggle("Sleep hours", isOn: $settings.sleepEnabled)
                if settings.sleepEnabled {
                    DatePicker("Bedtime", selection: timeBinding(settings, \.sleepStartMinutes), displayedComponents: .hourAndMinute)
                    DatePicker("Wake up", selection: timeBinding(settings, \.sleepEndMinutes), displayedComponents: .hourAndMinute)
                }
                Toggle("Stop reminders once today's goal is reached", isOn: $settings.stopWhenGoalReached)
            }

            Section {
                Button("Send a test reminder now") {
                    let msg = scheduler.makeMessage()
                    if settings.reminderStyle.usesGesture {
                        scheduler.presentCard?(msg.title, msg.body)
                    } else {
                        notifications.postNow(title: msg.title, body: msg.body)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            notifications.refreshStatus()
            cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        }
    }

    @ViewBuilder private var permissionRow: some View {
        LabeledContent("Notification permission") {
            switch notifications.authorizationStatus {
            case .authorized, .provisional:
                Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .denied:
                HStack {
                    Label("Blocked", systemImage: "xmark.circle.fill").foregroundStyle(.orange)
                    Button("Open System Settings") { SystemSettingsLinks.openNotifications() }
                }
            default:
                Button("Allow notifications") { notifications.requestAuthorization() }
            }
        }
    }

    @ViewBuilder private var cameraRow: some View {
        LabeledContent("Camera access") {
            switch cameraStatus {
            case .authorized:
                Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .denied, .restricted:
                HStack {
                    Label("Blocked", systemImage: "xmark.circle.fill").foregroundStyle(.orange)
                    Button("Open System Settings") { SystemSettingsLinks.openCameraPrivacy() }
                }
            default:
                Button("Allow camera") {
                    AVCaptureDevice.requestAccess(for: .video) { _ in
                        DispatchQueue.main.async { cameraStatus = AVCaptureDevice.authorizationStatus(for: .video) }
                    }
                }
            }
        }
    }
}

/// Learn or forget the owner's face, so only their sips close reminders.
private struct FaceSection: View {
    @EnvironmentObject var owner: OwnerFaceStore
    @EnvironmentObject var detector: DrinkingDetector

    var body: some View {
        Section("Recognise me") {
            if let p = detector.learningProgress {
                HStack(spacing: 16) {
                    ZStack {
                        if detector.state == .running {
                            CameraPreview(session: detector.session).clipShape(Circle())
                        } else {
                            Circle().fill(Theme.track)
                        }
                        Circle()
                            .trim(from: 0, to: p)
                            .stroke(.tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.2), value: p)
                    }
                    .frame(width: 96, height: 96)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Learning your face… \(Int(p * 100))%").font(.headline)
                        Text(detector.personVisible ? "Hold still and look at the camera." : "Move into view of the camera.")
                            .foregroundStyle(.secondary)
                        Button("Cancel") { detector.cancelLearning(); detector.stop() }
                    }
                }
                .padding(.vertical, 4)
            }
            LabeledContent("Your face") {
                if detector.learningProgress != nil {
                    EmptyView()
                } else if owner.isEnrolled {
                    HStack {
                        Label("Learned", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Button("Learn again") { detector.startLearning() }
                        Button("Forget", role: .destructive) { owner.forget() }
                    }
                } else {
                    Button("Learn my face") { detector.startLearning() }
                }
            }
            Text("Only your sips close a reminder. Anyone else drinking in front of the camera is ignored. SipBuddy stores a face signature on this Mac, never a photo. It's a likeness check, not Face ID.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct WeekdayPicker: View {
    @Binding var selection: Set<Int>
    private let cal = Calendar.current

    var body: some View {
        let order = (0..<7).map { (cal.firstWeekday - 1 + $0) % 7 + 1 }
        HStack(spacing: 4) {
            ForEach(order, id: \.self) { day in
                let on = selection.contains(day)
                Button {
                    if on { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(cal.veryShortWeekdaySymbols[day - 1])
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(on ? AnyShapeStyle(.tint) : AnyShapeStyle(Theme.track)))
                        .foregroundStyle(on ? Color.white : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(cal.weekdaySymbols[day - 1])
                .accessibilityLabel(cal.weekdaySymbols[day - 1])
                .accessibilityValue(on ? "On" : "Off")
            }
        }
    }
}

// MARK: - Personality

private struct PersonalitySettings: View {
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var scheduler: ReminderScheduler
    @State private var preview = ""

    var body: some View {
        Form {
            Section("Choose your buddy") {
                ForEach(Personality.allCases) { p in
                    Button {
                        settings.personality = p
                        refreshPreview()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: p.symbol)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.tint)
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(.tint.opacity(0.12)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.title).font(.system(size: 13, weight: .semibold))
                                Text(p.subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if settings.personality == p {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Section("Sounds like") {
                HStack(alignment: .top, spacing: 10) {
                    Text("💬")
                    Text(preview).font(.system(size: 13.5, weight: .medium, design: .rounded))
                    Spacer()
                    Button { refreshPreview() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless)
                        .help("Another example")
                }
            }
            Section {
                Toggle("Show time-of-day greetings", isOn: $settings.showGreetings)
                Text("Morning: “\(MessageLibrary.greetingSubtitle(personality: settings.personality, date: at(9)))”  ·  Afternoon: “\(MessageLibrary.greetingSubtitle(personality: settings.personality, date: at(14)))”  ·  Evening: “\(MessageLibrary.greetingSubtitle(personality: settings.personality, date: at(19)))”")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refreshPreview)
    }

    private func at(_ hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
    }

    private func refreshPreview() {
        preview = scheduler.makeMessage().body
    }
}

// MARK: - Appearance

private struct AppearanceSettings: View {
    @EnvironmentObject var settings: SettingsManager

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("Accent colour") {
                HStack(spacing: 14) {
                    ForEach(AccentChoice.allCases) { choice in
                        Button { settings.accent = choice } label: {
                            Circle()
                                .fill(choice.color)
                                .frame(width: 28, height: 28)
                                .overlay(Circle().strokeBorder(.white, lineWidth: settings.accent == choice ? 3 : 0))
                                .overlay(Circle().strokeBorder(choice.color, lineWidth: settings.accent == choice ? 1.5 : 0).padding(-3))
                        }
                        .buttonStyle(.plain)
                        .help(choice.label)
                        .accessibilityLabel(choice.label)
                    }
                }
                .padding(.vertical, 4)
            }
            Section("Preview") {
                HStack(spacing: 18) {
                    ZStack {
                        ProgressRing(progress: 0.62, accent: settings.accent.color, lineWidth: 8)
                        WaterDropView(progress: 0.62, accent: settings.accent.color).frame(width: 34, height: 46)
                    }
                    .frame(width: 84, height: 84)
                    VStack(alignment: .leading) {
                        Text("1,550 ml").font(.system(size: 20, weight: .bold, design: .rounded))
                        Text("of 2,500 ml goal").foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var hydration: HydrationManager
    @EnvironmentObject var launchAtLogin: LaunchAtLoginManager

    @State private var confirmReset = false
    @State private var exportMessage: String?

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch SipBuddy at login", isOn: Binding(get: { launchAtLogin.isEnabled },
                                                                  set: { launchAtLogin.setEnabled($0) }))
                if launchAtLogin.needsApproval {
                    HStack {
                        Text("Approve SipBuddy in Login Items.").font(.caption).foregroundStyle(.orange)
                        Button("Open Login Items") { launchAtLogin.openLoginItemsSettings() }
                    }
                }
                if let error = launchAtLogin.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
                Toggle("Show menu bar icon", isOn: $settings.showMenuBarIcon)
                if !settings.showMenuBarIcon {
                    Text("Reminders keep working. Open SipBuddy again from Applications to bring back Settings.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Data") {
                LabeledContent("History") {
                    Text("\(hydration.entries.count) entries stored on this Mac")
                        .foregroundStyle(.secondary)
                }
                Button("Export hydration history as CSV…", action: exportCSV)
                    .disabled(hydration.entries.isEmpty)
                if let exportMessage {
                    Text(exportMessage).font(.caption).foregroundStyle(.secondary)
                }
                Button("Reset today's progress…", role: .destructive) { confirmReset = true }
                    .disabled(hydration.todayEntries.isEmpty)
            }
            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                Text("Your data never leaves your Mac. No account, no cloud.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Quit SipBuddy") { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin.refresh() }
        .confirmationDialog("Reset today's progress?", isPresented: $confirmReset) {
            Button("Reset Today", role: .destructive) { hydration.resetToday() }
        } message: {
            Text("This removes today's \(hydration.todayEntries.count) entries. Earlier days are kept.")
        }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "SipBuddy-history-\(Date().formatted(.iso8601.year().month().day())).csv"
        panel.canCreateDirectories = true
        NSApp.activate()
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let csv = PersistenceManager.csv(for: hydration.entries, unit: settings.unit)
            do {
                try csv.write(to: url, atomically: true, encoding: .utf8)
                exportMessage = "Exported \(hydration.entries.count) entries to \(url.lastPathComponent)."
            } catch {
                exportMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }
}
