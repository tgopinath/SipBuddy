import SwiftUI

struct PopoverView: View {
    @EnvironmentObject var hydration: HydrationManager
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var notifications: NotificationManager
    @EnvironmentObject var menuBar: MenuBarManager

    @State private var editingEntry: WaterEntry?
    /// Today's sips and reminder status stay tucked away until asked for.
    @AppStorage("showPopoverDetails") private var showDetails = false

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 12) {
                PopoverHeader()
                ProgressCard()
                DrinkNowButton()
                if let toast = hydration.toast {
                    ToastView(toast: toast)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if showDetails {
                    TodayLogCard(editingEntry: $editingEntry)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    ReminderStatusCard()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                DetailsToggle(isOpen: $showDetails)
                if notifications.authorizationStatus == .denied && settings.reminderStyle == .notification {
                    PermissionBanner()
                }
                if let error = hydration.lastSaveError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
                PopoverFooter()
            }
            .padding(16)
            .frame(width: 348)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: hydration.toast)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: editingEntry)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showDetails)

            if hydration.celebrate {
                CelebrationView()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .background(Theme.background)
        .onAppear { notifications.refreshStatus() }
    }
}

// MARK: - Header

private struct PopoverHeader: View {
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var hydration: HydrationManager
    @EnvironmentObject var menuBar: MenuBarManager

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(MessageLibrary.greetingTitle())
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text(settings.showGreetings
                     ? MessageLibrary.greetingSubtitle(personality: settings.personality)
                     : "Let's stay hydrated today.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                Text(hydration.today.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 1)
            }
            Spacer()
            HStack(spacing: 4) {
                IconButton(symbol: "chart.bar.xaxis", help: "Statistics") { menuBar.showStatistics() }
                IconButton(symbol: "gearshape", help: "Settings") { menuBar.showSettings() }
            }
        }
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
                .background(Circle().fill(hovering ? Theme.track : .clear))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Progress

private struct ProgressCard: View {
    @EnvironmentObject var hydration: HydrationManager
    @EnvironmentObject var settings: SettingsManager

    var body: some View {
        let unit = settings.unit
        HStack(spacing: 18) {
            ZStack {
                ProgressRing(progress: hydration.progress, accent: settings.accent.color, lineWidth: 9)
                WaterDropView(progress: hydration.progress, accent: settings.accent.color)
                    .frame(width: 46, height: 62)
                    .offset(y: -2)
            }
            .frame(width: 108, height: 108)

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(unit.format(hydration.todayTotal))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("of \(unit.format(settings.dailyGoalML)) goal")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 14) {
                    MiniStat(label: "Remaining", value: unit.format(hydration.remainingToday))
                    MiniStat(label: "Done", value: "\(Int((hydration.progress * 100).rounded()))%")
                }
            }
            Spacer(minLength: 0)
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: hydration.todayTotal)
        .card()
    }
}

private struct MiniStat: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .contentTransition(.numericText())
        }
    }
}

// MARK: - Toast

private struct ToastView: View {
    @EnvironmentObject var hydration: HydrationManager
    let toast: Toast

    var body: some View {
        HStack {
            Text(toast.text)
                .font(.system(size: 12.5, weight: .medium))
            Spacer()
            if toast.canUndo {
                Button("Undo") { hydration.undoLast() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tint)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.tint.opacity(0.12)))
    }
}

// MARK: - Today's log

private struct TodayLogCard: View {
    @EnvironmentObject var hydration: HydrationManager
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var menuBar: MenuBarManager
    @Binding var editingEntry: WaterEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Today's sips")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("\(hydration.glassesToday)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(Theme.track))
                Spacer()
                Button("History") { menuBar.showStatistics() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.tint)
            }

            if let entry = editingEntry {
                EntryEditorView(entry: entry, isNew: false, onSave: { updated in
                    hydration.update(updated)
                    editingEntry = nil
                }, onDelete: {
                    hydration.delete(entry)
                    editingEntry = nil
                }, onCancel: { editingEntry = nil })
                .transition(.opacity)
            } else if hydration.todayEntries.isEmpty {
                Text("Nothing logged yet. Start with a glass! 💧")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 2) {
                    ForEach(hydration.todayEntries.suffix(3).reversed()) { entry in
                        EntryRow(entry: entry, onEdit: { editingEntry = entry }, onDelete: { hydration.delete(entry) })
                    }
                }
            }
        }
        .card()
    }
}

struct EntryRow: View {
    @EnvironmentObject var settings: SettingsManager
    let entry: WaterEntry
    var onEdit: () -> Void
    var onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            BlueDrop(size: 13)
                .frame(width: 24, height: 24)
                .background(Circle().fill(.tint.opacity(0.12)))
            Text(settings.unit.format(entry.amountML))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Spacer()
            Text(entry.date.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Menu {
                Button("Edit…", action: onEdit)
                Button("Delete", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .opacity(hovering ? 1 : 0.5)
            .accessibilityLabel("Entry options")
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? Theme.track.opacity(0.6) : .clear))
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Edit…", action: onEdit)
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}

// MARK: - Reminder status

private struct ReminderStatusCard: View {
    @EnvironmentObject var scheduler: ReminderScheduler
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var hydration: HydrationManager

    var body: some View {
        TimelineView(.periodic(from: .now, by: 20)) { context in
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(.tint.opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(now: context.date))
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(detail(now: context.date))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                controls
            }
        }
        .card(padding: 12)
    }

    private var symbol: String {
        if !settings.remindersEnabled { return "bell.slash" }
        if scheduler.isPaused { return "pause.fill" }
        if scheduler.nextReminderDate == nil && scheduler.isDoneForToday { return "checkmark" }
        return "bell.fill"
    }

    private func title(now: Date) -> String {
        if !settings.remindersEnabled { return "Reminders are off" }
        if scheduler.isPaused { return "Reminders paused" }
        guard let next = scheduler.nextReminderDate else {
            return "No upcoming reminders"
        }
        if scheduler.isDoneForToday && !Calendar.current.isDateInToday(next) {
            return "All done for today 🎉"
        }
        let cal = Calendar.current
        let time = next.formatted(date: .omitted, time: .shortened)
        if cal.isDateInToday(next) { return "Next sip at \(time)" }
        if cal.isDateInTomorrow(next) { return "Tomorrow at \(time)" }
        return "\(next.formatted(.dateTime.weekday(.wide))) at \(time)"
    }

    private func detail(now: Date) -> String {
        if !settings.remindersEnabled { return "Turn them on in Settings." }
        if scheduler.isPaused, let until = scheduler.pausedUntil {
            if until == .distantFuture { return "Until you resume" }
            return "Until \(until.formatted(date: Calendar.current.isDateInToday(until) ? .omitted : .abbreviated, time: .shortened))"
        }
        guard let next = scheduler.nextReminderDate else { return "Check your reminder days in Settings." }
        if scheduler.isDoneForToday && !Calendar.current.isDateInToday(next) {
            return "Reminders resume tomorrow."
        }
        return Self.relative(from: now, to: next)
    }

    static func relative(from now: Date, to date: Date) -> String {
        let minutes = max(0, Int(ceil(date.timeIntervalSince(now) / 60)))
        if minutes <= 1 { return "in less than a minute" }
        if minutes < 60 { return "in \(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "in \(h) h" : "in \(h) h \(m) min"
    }

    @ViewBuilder private var controls: some View {
        if !settings.remindersEnabled {
            Button("Turn on") { settings.remindersEnabled = true }
                .buttonStyle(SoftButtonStyle()).fixedSize()
        } else if scheduler.isPaused {
            Button("Resume") { scheduler.resume() }
                .buttonStyle(SoftButtonStyle(prominent: true)).fixedSize()
        } else {
            Menu {
                Section("Pause reminders") {
                    ForEach(PauseOption.allCases) { option in
                        Button(option.label) { scheduler.pause(option) }
                    }
                }
                Section("Snooze next reminder") {
                    Button("15 minutes") { scheduler.snooze(minutes: 15) }
                    Button("30 minutes") { scheduler.snooze(minutes: 30) }
                }
            } label: {
                Label("Pause", systemImage: "pause.circle")
                    .font(.system(size: 12, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}

private struct PermissionBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.badge.slash").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Notifications are blocked").font(.system(size: 12, weight: .semibold))
                Text("Allow SipBuddy in System Settings to get reminders.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open") { SystemSettingsLinks.openNotifications() }
                .buttonStyle(SoftButtonStyle()).fixedSize()
        }
        .card(padding: 10)
    }
}

/// Opens a "Drink now" session: drink in front of the camera and the sips are logged.
private struct DrinkNowButton: View {
    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var menuBar: MenuBarManager

    var body: some View {
        Button {
            menuBar.closePopover()
            appModel.card.startDrinkSession()
        } label: {
            HStack(spacing: 8) {
                BlueDrop(size: 14)
                    .padding(3)
                    .background(Circle().fill(.white))
                Text("Drink now — I'll count your swallows")
            }
        }
        .buttonStyle(SoftButtonStyle(prominent: true))
        .help("Drink in front of the camera; SipBuddy logs the water for you")
    }
}

/// One quiet row that reveals or hides today's sips and the reminder status.
private struct DetailsToggle: View {
    @EnvironmentObject var hydration: HydrationManager
    @Binding var isOpen: Bool
    @State private var hovering = false

    var body: some View {
        Button { isOpen.toggle() } label: {
            HStack(spacing: 6) {
                Text(isOpen ? "Hide details" : "Show today's sips (\(hydration.glassesToday)) & reminders")
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(hovering ? Theme.track.opacity(0.6) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(isOpen ? "Hide details" : "Show today's sips and reminders")
    }
}

private struct PopoverFooter: View {
    @EnvironmentObject var settings: SettingsManager

    var body: some View {
        HStack {
            Label(settings.personality.title, systemImage: settings.personality.symbol)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 4)
    }
}

enum SystemSettingsLinks {
    static func openNotifications() {
        let id = Bundle.main.bundleIdentifier ?? ""
        let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)")
            ?? URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!
        NSWorkspace.shared.open(url)
    }

    static func openCameraPrivacy() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }
}
