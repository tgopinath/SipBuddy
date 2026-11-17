import SwiftUI

/// The reminder as a full-screen takeover. It closes once the camera sees you drinking.
struct FullScreenReminderView: View {
    let controller: ReminderCardController
    /// The display with the camera shows the live view; other displays point to it.
    var isCameraScreen = true
    @EnvironmentObject var model: ReminderCardModel
    @EnvironmentObject var detector: DrinkingDetector
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var hydration: HydrationManager

    @State private var bob = false

    private var accent: Color { settings.accent.color }
    private var cameraBlocked: Bool { detector.state == .denied || detector.state == .unavailable }
    private var allowManualClose: Bool { !settings.gestureOnlyDismiss || cameraBlocked }

    var body: some View {
        ZStack {
            // Deep navy wash over the blurred desktop.
            LinearGradient(colors: [Color(red: 0.03, green: 0.08, blue: 0.20).opacity(0.82),
                                    Color(red: 0.02, green: 0.18, blue: 0.32).opacity(0.78)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            if model.isVisible {
                content
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }

            // Close button, always available in the top-right corner.
            if model.isVisible {
                VStack {
                    HStack {
                        Spacer()
                        Button { controller.dismiss(byDrinking: false) } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .bold))
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(.white.opacity(0.15)))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .help("Dismiss")
                    }
                    Spacer()
                }
                .padding(32)
            }

            if model.dismissing {
                ZStack {
                    accent.opacity(0.9).ignoresSafeArea()
                    Label(model.loggedAmount.map { "Logged \($0) 💧" } ?? "Nicely done! 💧", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .transition(.opacity)
            }
        }
        .foregroundStyle(.white)
        .tint(accent)
        .animation(.easeOut(duration: 0.2), value: model.dismissing)
    }

    private var content: some View {
        VStack(spacing: 34) {
            WaterDropView(progress: hydration.progress, accent: accent)
                .frame(width: 96, height: 128)
                .offset(y: bob ? -8 : 4)
                .animation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true), value: bob)
                .onAppear { bob = true }

            VStack(spacing: 12) {
                Text(model.title)
                    .font(.system(size: 18, weight: .semibold))
                    .opacity(0.7)
                Text(model.message)
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 900)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(settings.unit.format(hydration.todayTotal)) of \(settings.unit.format(settings.dailyGoalML)) today")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .opacity(0.7)
                if detector.sipCount > 0 {
                    Text("≈ \(settings.unit.format(controller.estimatedML)) so far · \(detector.sipCount) of \(DrinkingDetector.requiredSips) swallows")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.aqua)
                }
            }

            if isCameraScreen { gesturePanel } else { otherScreenHint }

            if isCameraScreen && !detector.owner.isEnrolled && detector.learningProgress == nil && detector.state == .running {
                Button("🙂 Learn my face") { detector.startLearning() }
                    .buttonStyle(BigButtonStyle(prominent: true))
            }

            if allowManualClose {
                Button("Snooze 15 min") { controller.snooze(minutes: 15) }
                    .buttonStyle(BigButtonStyle())
            }
        }
        .padding(40)
    }

    private var gesturePanel: some View {
        VStack(spacing: 16) {
            ZStack {
                if settings.showCameraPreview && detector.state == .running {
                    CameraPreview(session: detector.session)
                        .clipShape(Circle())
                } else {
                    Circle().fill(.white.opacity(0.12))
                    Text("🥛").font(.system(size: 64))
                }
                Circle()
                    .stroke(.white.opacity(0.18), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: detector.learningProgress ?? detector.closeProgress)
                    .stroke(Theme.aqua, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.08), value: detector.closeProgress)
            }
            .frame(width: 180, height: 180)
            .overlay(SwallowPop(count: detector.sipCount, label: "+\(settings.unit.format(settings.mlPerSip))",
                                size: 30, playSound: settings.soundEnabled))

            VStack(spacing: 4) {
                Text(detector.statusTitle)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Text(detector.statusDetail)
                    .font(.system(size: 14))
                    .opacity(0.7)
            }
            if detector.state == .timedOut {
                Button("Look again") { controller.retryCamera() }.buttonStyle(BigButtonStyle())
            } else if detector.state == .denied {
                Button("Allow camera in System Settings") { SystemSettingsLinks.openCameraPrivacy() }
                    .buttonStyle(BigButtonStyle())
            }
        }
    }
}

extension FullScreenReminderView {
    fileprivate var otherScreenHint: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(.white.opacity(0.12))
                Text("🥛").font(.system(size: 44))
                Circle()
                    .trim(from: 0, to: detector.closeProgress)
                    .stroke(Theme.aqua, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 110, height: 110)
            Text(detector.sipCount > 0 ? "Swallow \(detector.sipCount) of \(DrinkingDetector.requiredSips) 💧" : "Drink in front of the camera on your main screen")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
            Text("This reminder closes on every screen at once.")
                .font(.system(size: 14)).opacity(0.7)
        }
    }
}

private struct BigButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .padding(.horizontal, 26)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(Capsule().fill(prominent ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.white.opacity(configuration.isPressed ? 0.25 : 0.15))))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
