import SwiftUI
import AVFoundation

/// The corner reminder. In strict mode it has no close button: it closes once the
/// camera sees you drinking.
struct ReminderCardView: View {
    let controller: ReminderCardController
    @EnvironmentObject var model: ReminderCardModel
    @EnvironmentObject var detector: DrinkingDetector
    @EnvironmentObject var settings: SettingsManager

    @State private var bob = false

    /// When the camera can't help, never trap the user with an undismissable card.
    private var cameraBlocked: Bool {
        detector.state == .denied || detector.state == .unavailable
    }
    private var allowManualClose: Bool { !settings.gestureOnlyDismiss || cameraBlocked }

    var body: some View {
        VStack(spacing: 0) {
            if model.isVisible {
                card
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        .frame(width: 400, height: 300, alignment: .top)
        .tint(settings.accent.color)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                DropShape()
                    .fill(Theme.waterGradient(settings.accent.color))
                    .frame(width: 26, height: 34)
                    .offset(y: bob ? -3 : 2)
                    .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: bob)
                    .onAppear { bob = true }
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(model.message)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                    if detector.sipCount > 0 {
                        Text("≈ \(settings.unit.format(controller.estimatedML)) so far · \(detector.sipCount) swallows")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.tint)
                    }
                }
                Spacer(minLength: 0)
                // Always available, top right.
                Button { controller.dismiss(byDrinking: false) } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Theme.track))
                }
                .buttonStyle(.plain)
                .help("Close")
            }

            gestureRow
            if !detector.owner.isEnrolled && detector.learningProgress == nil && detector.state == .running {
                Button("🙂 Learn my face") { detector.startLearning() }
                    .buttonStyle(SoftButtonStyle(prominent: true))
            }

            if allowManualClose {
                Button("Snooze 15 min") { controller.snooze(minutes: 15) }
                    .buttonStyle(SoftButtonStyle())
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.background)
                .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
        )
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.cardBorder))
        .overlay {
            if model.dismissing {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.tint.opacity(0.92))
                    .overlay(
                        Label(model.loggedAmount.map { "Logged \($0) 💧" } ?? "Nicely done! 💧", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    )
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.dismissing)
        .padding(10)
    }

    @ViewBuilder private var gestureRow: some View {
        HStack(spacing: 12) {
            ZStack {
                if settings.showCameraPreview && detector.state == .running {
                    CameraPreview(session: detector.session)
                        .clipShape(Circle())
                } else {
                    Circle().fill(Theme.track)
                    Text("🥛").font(.system(size: 22))
                }
                Circle()
                    .trim(from: 0, to: detector.closeProgress)
                    .stroke(.tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.08), value: detector.closeProgress)
            }
            .frame(width: 48, height: 48)
            .overlay(SwallowPop(count: detector.sipCount, label: "+\(settings.unit.format(settings.mlPerSip))",
                                size: 16, playSound: settings.soundEnabled))

            VStack(alignment: .leading, spacing: 2) {
                Text(gestureTitle).font(.system(size: 12.5, weight: .semibold))
                Text(gestureDetail).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if detector.state == .timedOut {
                Button("Look again") { controller.retryCamera() }
                    .buttonStyle(SoftButtonStyle()).fixedSize()
            } else if detector.state == .denied {
                Button("Allow") { SystemSettingsLinks.openCameraPrivacy() }
                    .buttonStyle(SoftButtonStyle()).fixedSize()
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
    }

    private var gestureTitle: String { detector.statusTitle }
    private var gestureDetail: String { detector.statusDetail }
}

extension DrinkingDetector {
    var statusTitle: String {
        switch state {
        case .running:
            if let p = learningProgress { return "Learning your face… \(Int(p * 100))% — look at the camera" }
            if !owner.isEnrolled { return "Let me learn your face first 🙂" }
            if strangerVisible { return "I don't recognise you 🙅 — only my owner's sips count" }
            if inSession {
                if isDrinking || sipCount > 0 { return "Swallow \(sipCount) 💧 — keep going" }
                return vesselVisible ? "I see your bottle — take a sip! 🥤" : "Take your sips 🥤"
            }
            if isDrinking || sipCount > 0 { return "Swallow \(min(sipCount, Self.requiredSips)) of \(Self.requiredSips) 💧" }
            if vesselVisible { return "I see your bottle — take a sip! 🥤" }
            return personVisible ? "Grab your bottle and take a sip 🥤" : "Take 5 swallows to close 🥤"
        case .requestingAccess: return "Allow camera access so I can see you sip"
        case .denied: return "Camera access is off"
        case .unavailable: return "No camera found"
        case .timedOut: return "Camera paused to save battery"
        case .idle: return "Take 5 swallows to close 🥤"
        }
    }

    var statusDetail: String {
        switch state {
        case .running where learningProgress != nil: return "Keep your face in view for a few seconds."
        case .running where inSession: return "I'll log your water about 5 seconds after you stop."
        case .running where !owner.isEnrolled: return "So only your sips count. Look at the camera for about 3 seconds."
        case .running: return "Drink from your bottle or cup — I count each swallow at your throat. Nothing is recorded or saved."
        case .requestingAccess: return "Used only while a reminder is showing."
        case .denied: return "Allow it in System Settings, or close with ✕."
        case .unavailable: return "You can close this with ✕."
        case .timedOut: return "The reminder stays until you drink."
        case .idle: return "Starting camera…"
        }
    }
}

/// Live, mirrored camera preview so you can see your hand in frame.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.connection?.automaticallyAdjustsVideoMirroring = false
        layer.connection?.isVideoMirrored = true
        layer.frame = view.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer = CALayer()
        view.layer?.addSublayer(layer)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
