import AVFoundation
import Vision
import Combine

/// Decides from one camera frame whether the person in front of the camera is drinking:
/// a bottle or cup is in view near their face and their hand (or wrist) is up at their mouth.
enum DrinkingClassifier {
    /// What Vision saw in one frame, in normalized image coordinates.
    struct Frame {
        var mouth: CGPoint?            // centre of the lips, from face landmarks
        var faceWidth: CGFloat?        // width of the face box
        var nose: CGPoint?             // from body pose, used when the face is hidden by the glass
        var shoulderWidth: CGFloat?
        var handPoints: [CGPoint] = [] // hand joints near the person
        var wrists: [CGPoint] = []
    }

    /// Faces narrower than this are people in the background and are ignored.
    static let minimumFaceWidth: CGFloat = 0.08

    /// Vision image-classifier labels that mean "something you drink from".
    static let vesselLabels: Set<String> = [
        "bottle", "wine_bottle", "cup", "mug", "drinking_glass", "jug", "thermos",
        "straw_drinking", "decanter", "drink", "tea_drink",
    ]
    /// Minimum classifier confidence for a bottle or cup to count as seen.
    static let vesselThreshold: Float = 0.03

    /// Highest confidence among drink-container labels.
    static func vesselConfidence(_ labels: [(identifier: String, confidence: Float)]) -> Float {
        labels.filter { vesselLabels.contains($0.identifier) }.map(\.confidence).max() ?? 0
    }

    /// Where the mouth is (from the face if visible, else just below the nose) and the face scale.
    static func mouth(_ f: Frame) -> (point: CGPoint, scale: CGFloat)? {
        guard let scale = f.faceWidth ?? f.shoulderWidth.map({ $0 * 0.45 }), scale >= minimumFaceWidth,
              let point = f.mouth ?? f.nose.map({ CGPoint(x: $0.x, y: $0.y - scale * 0.3) }) else { return nil }
        return (point, scale)
    }

    /// Drinking = a bottle or cup was seen near the face and a hand (or the wrist holding it)
    /// is within about one face-width of the mouth.
    static func isDrinking(_ f: Frame, vesselSeen: Bool) -> Bool {
        guard vesselSeen, let m = mouth(f) else { return false }
        return (f.handPoints + f.wrists).contains { distance($0, m.point) <= m.scale * 1.4 }
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}

/// Spots swallows in the up-and-down motion of the throat (the Adam's apple rises and
/// falls on every swallow). Input is the throat's vertical motion minus the head's, from
/// optical flow; a swallow is a movement one way followed by the other within a second.
struct SwallowDetector {
    /// Smallest motion (flow pixels per frame) that can count, whatever the noise.
    static let minThreshold: Float = 0.08
    /// A rise must be followed by the fall within this long.
    static let pairWindow: TimeInterval = 1.0
    /// No second swallow sooner than this.
    static let refractory: TimeInterval = 0.6

    private(set) var noise: Float = 0.05
    private var firstPulse: (sign: Float, at: Date)?
    private var lastSwallowAt = Date.distantPast

    var threshold: Float { max(Self.minThreshold, noise * 4) }

    /// Feeds one motion sample; returns true when a swallow completes.
    mutating func feed(_ motion: Float, at now: Date) -> Bool {
        let t = threshold
        let size = abs(motion)
        if size < t {
            // Quiet frames teach the detector how jittery the picture is.
            noise = noise * 0.95 + size * 0.05
            if let p = firstPulse, now.timeIntervalSince(p.at) > Self.pairWindow { firstPulse = nil }
            return false
        }
        let sign: Float = motion > 0 ? 1 : -1
        if let p = firstPulse, p.sign != sign, now.timeIntervalSince(p.at) <= Self.pairWindow,
           now.timeIntervalSince(lastSwallowAt) >= Self.refractory {
            firstPulse = nil
            lastSwallowAt = now
            return true
        }
        if firstPulse == nil || firstPulse!.sign != sign { firstPulse = (sign, now) }
        return false
    }
}

/// Counts swallows while you drink. A drinking episode runs from lifting the bottle to
/// your mouth until shortly after you lower it. Swallows seen at the throat are counted
/// one by one; when the throat isn't visible, the episode is estimated from its length
/// (one swallow per `continuousSip` seconds, at least one for a real sip).
struct SipCounter {
    static let minSip: TimeInterval = 0.6
    static let continuousSip: TimeInterval = 1.5
    /// The episode stays open this long after the bottle comes down: people often swallow
    /// just after lowering it.
    static let gap: TimeInterval = 1.2

    private(set) var completed = 0
    private var episodeStart: Date?
    private var lastDrinkingAt: Date?
    private var episodeSwallows = 0

    /// Swallows so far, including the episode in progress.
    func total(at now: Date) -> Int {
        completed + episodeCount(endingAt: lastDrinkingAt ?? now)
    }

    private func episodeCount(endingAt end: Date) -> Int {
        guard let start = episodeStart else { return 0 }
        if episodeSwallows > 0 { return episodeSwallows }
        return Int(end.timeIntervalSince(start) / Self.continuousSip)
    }

    /// A swallow seen at the throat; only counts during a drinking episode.
    mutating func addSwallow() {
        if episodeStart != nil { episodeSwallows += 1 }
    }

    mutating func update(drinking: Bool, at now: Date) {
        if drinking {
            if episodeStart == nil { episodeStart = now; episodeSwallows = 0 }
            lastDrinkingAt = now
        } else if let start = episodeStart, let last = lastDrinkingAt, now.timeIntervalSince(last) > Self.gap {
            let duration = last.timeIntervalSince(start)
            if episodeSwallows > 0 {
                completed += episodeSwallows
            } else if duration >= Self.minSip {
                completed += max(1, Int(duration / Self.continuousSip))
            }
            episodeStart = nil
            lastDrinkingAt = nil
            episodeSwallows = 0
        }
    }
}

/// Runs the camera only while a reminder is on screen and reports once you've taken
/// enough sips.
final class DrinkingDetector: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    enum State: Equatable { case idle, requestingAccess, running, denied, unavailable, timedOut }

    @Published private(set) var state: State = .idle
    @Published private(set) var personVisible = false
    @Published private(set) var isDrinking = false
    @Published private(set) var vesselVisible = false
    /// The owner's face was recognised recently. Only the owner's sips count.
    @Published private(set) var ownerRecognized = false
    /// Someone is in front of the camera but it isn't the owner.
    @Published private(set) var strangerVisible = false
    /// Learning the owner's face: 0…1 while learning, nil otherwise.
    @Published private(set) var learningProgress: Double?
    @Published private(set) var drinkProgress: Double = 0
    @Published private(set) var sipCount = 0
    /// Progress toward closing, for the progress ring.
    var closeProgress: Double { drinkProgress }

    /// Sips needed before drinking closes the reminder.
    static let requiredSips = 5
    /// In a "Drink now" session: finish this long after the last sip.
    static let sessionIdle: TimeInterval = 5
    /// In a "Drink now" session: give up if no sip starts within this time.
    static let sessionNoSipTimeout: TimeInterval = 60

    /// "Drink now" mode: count every sip and finish once you stop, instead of
    /// waiting for a fixed number of sips.
    private(set) var isSession = false
    /// Main-thread copy for the UI.
    @Published private(set) var inSession = false
    private var sessionStart = Date()
    private var lastDrinkFrameAt: Date?
    /// The face is often hidden by the glass mid-sip; remember where it was this long.
    static let faceMemory: TimeInterval = 6
    /// Stop the camera if nobody responds, to save battery and privacy. The reminder stays.
    static let cameraTimeout: TimeInterval = 10 * 60

    /// Called once, after enough sips.
    var onDrinking: (() -> Void)?

    let owner: OwnerFaceStore
    /// Recognition carries through the sip, when the bottle hides the face.
    static let ownerMemory: TimeInterval = 8
    private var lastOwnerAt: Date?
    private var lastIdentityCheck = Date.distantPast
    private var learningSamples: [VNFeaturePrintObservation] = []
    private var lastLearnSample = Date.distantPast

    init(owner: OwnerFaceStore) {
        self.owner = owner
        super.init()
    }

    /// Asks for camera access up front, so the permission dialog never appears
    /// behind a full-screen reminder.
    func requestAccessIfNeeded() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined else { return }
        AVCaptureDevice.requestAccess(for: .video) { granted in
            if granted { self.prepare() }
        }
    }

    /// Learns the owner's face from the live camera. Look at the camera for a few seconds.
    func startLearning() {
        queue.async {
            self.learningSamples = []
            self.lastLearnSample = .distantPast
            self.learningProgressValue = 0
        }
        learningProgress = 0
        if state != .running { start() }
    }

    /// Called on the main queue once the owner's face has been learned.
    var onLearningFinished: (() -> Void)?

    func cancelLearning() {
        learningProgress = nil
        queue.async { self.learningProgressValue = nil }
    }

    /// Camera-queue copy of "are we learning".
    private var learningProgressValue: Double?

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.sipbuddy.camera", qos: .userInitiated)
    /// Fast face box, every frame.
    private let faceBoxRequest = VNDetectFaceRectanglesRequest()
    /// Detailed lips position, every few frames (the mouth barely moves within the face box).
    private let faceRequest = VNDetectFaceLandmarksRequest()
    private var frameIndex = 0
    /// Where the lips sit inside the face box, from the last landmarks pass.
    private var mouthInBox = CGPoint(x: 0.5, y: 0.22)
    private let handRequest: VNDetectHumanHandPoseRequest = {
        let r = VNDetectHumanHandPoseRequest()
        r.maximumHandCount = 2
        return r
    }()
    private let bodyRequest = VNDetectHumanBodyPoseRequest()
    private let classifyRequest = VNClassifyImageRequest()
    private var lastClassify = Date.distantPast
    private var lastVesselAt: Date?
    private var classifyAroundFace = false
    /// A bottle seen this recently still counts (it can be hidden by the hand mid-sip).
    static let vesselMemory: TimeInterval = 5
    private var configured = false
    private var lastFrame = Date.distantPast
    private var sips = SipCounter()
    private var lastFace: (mouth: CGPoint, width: CGFloat, box: CGRect, at: Date)?
    private var swallows = SwallowDetector()
    private var previousPixels: CVPixelBuffer?
    /// Throat motion is checked only around drinking, to keep CPU use low.
    private var throatWatchUntil = Date.distantPast

    private var fired = false
    private var timeoutWork: DispatchWorkItem?

    /// Sets up the capture pipeline in advance (camera stays off) so the first
    /// reminder starts watching straight away.
    func prepare() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        queue.async { if !self.configured { _ = self.configure() } }
    }

    func start(session: Bool = false) {
        inSession = session
        queue.async {
            self.isSession = session
            self.sessionStart = Date()
            self.lastDrinkFrameAt = nil
        }
        queue.async {
            self.fired = false
            self.sips = SipCounter()
            self.lastFace = nil
            self.swallows = SwallowDetector()
            self.previousPixels = nil
            self.lastPublished = nil
            self.drinkProgressValue = 0
            self.lastVesselAt = nil
            self.lastOwnerAt = nil
        }
        drinkProgress = 0
        sipCount = 0
        isDrinking = false
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run()
        case .notDetermined:
            state = .requestingAccess
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { self.run() } else { self.state = .denied }
                }
            }
        default:
            state = .denied
            #if DEBUG
            Self.debugLog("camera DENIED")
            #endif
        }
    }

    func stop() {
        timeoutWork?.cancel()
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
        DispatchQueue.main.async {
            if self.state == .running { self.state = .idle }
            self.personVisible = false
            self.isDrinking = false
            self.vesselVisible = false
            self.drinkProgress = 0
        }
    }

    private func run() {
        queue.async {
            if !self.configured {
                guard self.configure() else {
                    DispatchQueue.main.async { self.state = .unavailable }
                    return
                }
            }
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async {
                self.state = .running
                self.armTimeout()
            }
            #if DEBUG
            Self.debugLog("camera running")
            #endif
        }
    }

    private func armTimeout() {
        timeoutWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.state == .running else { return }
            self.stop()
            self.state = .timedOut
        }
        timeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.cameraTimeout, execute: work)
    }

    private func configure() -> Bool {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video, position: .unspecified)
        guard let device = discovery.devices.first ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }

        session.beginConfiguration()
        if session.canSetSessionPreset(.vga640x480) {
            session.sessionPreset = .vga640x480
        } else if session.canSetSessionPreset(.medium) {
            session.sessionPreset = .medium
        }
        guard session.canAddInput(input) else { session.commitConfiguration(); return false }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { session.commitConfiguration(); return false }
        session.addOutput(output)
        session.commitConfiguration()
        configured = true
        return true
    }

    // MARK: - Frames

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let now = Date()
        let dt = now.timeIntervalSince(lastFrame)
        guard dt >= 0.08, !fired else { return }  // ~12 fps: enough to catch a swallow, light on CPU
        lastFrame = now

        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up, options: [:])
        do {
            // Heavy passes are spread across frames; their last results carry over in between.
            frameIndex += 1
            try handler.perform([faceBoxRequest])
            // Nobody in view (and nobody seen recently): skip the heavy passes entirely.
            let faceNow = !(faceBoxRequest.results ?? []).isEmpty
            let faceRecent = lastFace.map { now.timeIntervalSince($0.at) <= Self.faceMemory } ?? false
            guard faceNow || faceRecent || learningProgressValue != nil else {
                publish(person: false, vessel: false, owner: false, stranger: false,
                        drinking: false, progress: drinkProgressValue, sips: sips.total(at: now), fire: false)
                return
            }
            var requests: [VNRequest] = [handRequest]
            if frameIndex % 3 == 0 { requests.append(faceRequest) }
            if frameIndex % 4 == 1 { requests.append(bodyRequest) }
            try handler.perform(requests)
        } catch {
            return
        }

        let frame = makeFrame(now: now)
        let largestFace = (faceBoxRequest.results ?? []).max { $0.boundingBox.width < $1.boundingBox.width }
        let pixels = CMSampleBufferGetImageBuffer(sampleBuffer)

        // Learning the owner's face.
        if learningProgressValue != nil {
            if let face = largestFace, let pixels, face.boundingBox.width >= DrinkingClassifier.minimumFaceWidth,
               now.timeIntervalSince(lastLearnSample) >= 0.25,
               let print = owner.featurePrint(of: pixels, faceBox: face.boundingBox) {
                lastLearnSample = now
                learningSamples.append(print)
            }
            let done = learningSamples.count >= OwnerFaceStore.samplesNeeded
            let progress = Double(learningSamples.count) / Double(OwnerFaceStore.samplesNeeded)
            let samples = learningSamples
            let faceInView = largestFace != nil
            DispatchQueue.main.async {
                if self.personVisible != faceInView { self.personVisible = faceInView }
                if done {
                    self.owner.save(samples: samples)
                    self.learningProgress = nil
                    self.onLearningFinished?()
                    #if DEBUG
                    Self.debugLog("learned owner face, threshold=\(self.owner.threshold)")
                    #endif
                } else if self.learningProgress != nil {
                    self.learningProgress = progress
                }
            }
            if done { learningProgressValue = nil }
            return
        }

        // Who is in front of the camera? Checked twice a second on the closest face.
        var ownerDistance: Float = -1
        if owner.isEnrolled, let face = largestFace, let pixels, now.timeIntervalSince(lastIdentityCheck) >= 1.0 {
            lastIdentityCheck = now
            if let print = owner.featurePrint(of: pixels, faceBox: face.boundingBox) {
                ownerDistance = owner.distance(to: print) ?? -1
                if owner.isOwner(print) { lastOwnerAt = now } else { lastOwnerAt = nil }
            }
        }
        // Recognise the owner first: until their face is learned, no one's sips count.
        let ownerPresent = owner.isEnrolled
            && (lastOwnerAt.map { now.timeIntervalSince($0) <= Self.ownerMemory } ?? false)

        // Look for a bottle or cup a few times a second: around the face when we know
        // where it is, alternating with the whole frame (a raised bottle can hide the face).
        var vesselConf: Float = -1
        var vesselLabelsSeen = ""
        if now.timeIntervalSince(lastClassify) >= 0.4 {
            lastClassify = now
            classifyAroundFace.toggle()
            if classifyAroundFace, let m = DrinkingClassifier.mouth(frame) {
                let side = min(1, m.scale * 5)
                let x = min(max(0, m.point.x - side / 2), 1 - side)
                let y = min(max(0, m.point.y - side * 0.6), 1 - side)
                classifyRequest.regionOfInterest = CGRect(x: x, y: y, width: side, height: side)
            } else {
                classifyRequest.regionOfInterest = CGRect(x: 0, y: 0, width: 1, height: 1)
            }
            if (try? handler.perform([classifyRequest])) != nil {
                let labels = (classifyRequest.results ?? []).map { ($0.identifier, $0.confidence) }
                vesselConf = DrinkingClassifier.vesselConfidence(labels)
                if vesselConf >= DrinkingClassifier.vesselThreshold { lastVesselAt = now }
                vesselLabelsSeen = labels.filter { DrinkingClassifier.vesselLabels.contains($0.0) && $0.1 > 0.01 }
                    .map { "\($0.0)=\(String(format: "%.2f", $0.1))" }.joined(separator: " ")
                let topScene = labels.sorted { $0.1 > $1.1 }.prefix(3).map { "\($0.0)=\(String(format: "%.2f", $0.1))" }
                vesselLabelsSeen += " | top: " + topScene.joined(separator: " ")
            }
        }
        let vesselSeen = lastVesselAt.map { now.timeIntervalSince($0) <= Self.vesselMemory } ?? false
        // Only the owner's sips count.
        let drinking = ownerPresent && DrinkingClassifier.isDrinking(frame, vesselSeen: vesselSeen)
        let person = frame.faceWidth != nil || frame.nose != nil

        // Throat: count swallows from the motion just below the chin.
        var throatMotion: Float?
        var swallowed = false
        if drinking { throatWatchUntil = now.addingTimeInterval(SipCounter.gap + 0.5) }
        if now <= throatWatchUntil, let pixels, let box = lastFace?.box {
            throatMotion = throatVerticalMotion(current: pixels, faceBox: box)
            if let m = throatMotion, swallows.feed(m, at: now) {
                sips.update(drinking: drinking, at: now)
                sips.addSwallow()
                swallowed = true
            }
        }
        previousPixels = pixels

        sips.update(drinking: drinking, at: now)
        let sipTotal = sips.total(at: now)
        #if DEBUG
        Self.debugLog(String(format: "throat=%@ thr=%.2f%@ ", throatMotion.map { String(format: "%+.2f", $0) } ?? "-", swallows.threshold, swallowed ? " SWALLOW" : "") + String(format: "owner=%@ dist=%.3f/%.3f ", ownerPresent ? "Y" : "n", ownerDistance, owner.threshold) + String(format: "face=%@ nose=%@ hands=%d wrists=%d mouthNear=%@ vesselSeen=%@ drinking=%@ sips=%d %@",
                             frame.faceWidth.map { String(format: "%.2f", $0) } ?? "-",
                             frame.nose == nil ? "-" : "y", frame.handPoints.count, frame.wrists.count,
                             DrinkingClassifier.isDrinking(frame, vesselSeen: true) ? "Y" : "n",
                             vesselSeen ? "Y" : "n", drinking ? "Y" : "n", sipTotal,
                             vesselConf >= 0 ? String(format: "vessel=%.2f [%@]", vesselConf, vesselLabelsSeen) : ""))
        #endif
        if drinking { lastDrinkFrameAt = now }
        let progress = isSession ? 0 : min(1, Double(sipTotal) / Double(Self.requiredSips))


        let sessionDone = isSession && (
            (sipTotal > 0 && !drinking && now.timeIntervalSince(lastDrinkFrameAt ?? now) >= Self.sessionIdle)
            || (sipTotal == 0 && lastDrinkFrameAt == nil && now.timeIntervalSince(sessionStart) >= Self.sessionNoSipTimeout))
        let shouldFire = (progress >= 1 || sessionDone) && !fired
        if shouldFire { fired = true }

        drinkProgressValue = progress
        publish(person: person, vessel: vesselSeen, owner: owner.isEnrolled && ownerPresent,
                stranger: owner.isEnrolled && !ownerPresent && largestFace != nil,
                drinking: drinking, progress: progress, sips: sipTotal, fire: shouldFire)
    }

    private var drinkProgressValue: Double = 0
    private struct UIState: Equatable {
        var person, vessel, owner, stranger, drinking: Bool
        var progress: Double
        var sips: Int
    }
    private var lastPublished: UIState?

    /// Sends state to the UI only when it changed, so the screens aren't redrawn every frame.
    private func publish(person: Bool, vessel: Bool, owner: Bool, stranger: Bool,
                         drinking: Bool, progress: Double, sips: Int, fire: Bool) {
        let snapshot = UIState(person: person, vessel: vessel, owner: owner, stranger: stranger,
                               drinking: drinking, progress: (progress * 20).rounded() / 20, sips: sips)
        if !fire, let last = lastPublished, last == snapshot { return }
        lastPublished = snapshot
        DispatchQueue.main.async {
            if self.personVisible != person { self.personVisible = person }
            if self.vesselVisible != vessel { self.vesselVisible = vessel }
            if self.ownerRecognized != owner { self.ownerRecognized = owner }
            if self.strangerVisible != stranger { self.strangerVisible = stranger }
            if self.isDrinking != drinking { self.isDrinking = drinking }
            if self.drinkProgress != snapshot.progress { self.drinkProgress = snapshot.progress }
            if self.sipCount != sips { self.sipCount = sips }
            if fire { self.onDrinking?() }
        }
    }

    /// Vertical motion of the throat relative to the forehead (so nodding or leaning
    /// doesn't count), from optical flow between the previous and current frames.
    private func throatVerticalMotion(current: CVPixelBuffer, faceBox box: CGRect) -> Float? {
        guard let previous = previousPixels else { return nil }
        // Normalized Vision rects (origin bottom-left).
        let throat = CGRect(x: box.midX - box.width * 0.3, y: box.minY - box.height * 0.55,
                            width: box.width * 0.6, height: box.height * 0.5)
        let forehead = CGRect(x: box.midX - box.width * 0.25, y: box.maxY - box.height * 0.28,
                              width: box.width * 0.5, height: box.height * 0.22)
        // Compute flow only for the face-and-neck area, which is much faster than the whole frame.
        let roi = throat.union(forehead).insetBy(dx: -box.width * 0.1, dy: -box.height * 0.05)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard roi.width > 0.02, roi.height > 0.02 else { return nil }

        let request = VNGenerateOpticalFlowRequest(targetedCVPixelBuffer: previous, options: [:])
        request.computationAccuracy = .low
        request.outputPixelFormat = kCVPixelFormatType_TwoComponent32Float
        request.regionOfInterest = roi
        guard (try? VNImageRequestHandler(cvPixelBuffer: current, options: [:]).perform([request])) != nil,
              let flow = request.results?.first?.pixelBuffer else { return nil }

        func inROI(_ r: CGRect) -> CGRect {
            CGRect(x: (r.minX - roi.minX) / roi.width, y: (r.minY - roi.minY) / roi.height,
                   width: r.width / roi.width, height: r.height / roi.height)
        }
        guard let t = Self.meanVerticalFlow(flow, in: inROI(throat)),
              let f = Self.meanVerticalFlow(flow, in: inROI(forehead)) else { return nil }
        return t - f
    }

    /// Average vertical flow inside a normalized rect of a two-channel float flow buffer.
    static func meanVerticalFlow(_ flow: CVPixelBuffer, in rect: CGRect) -> Float? {
        let r = rect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard r.width > 0.01, r.height > 0.01 else { return nil }
        CVPixelBufferLockBaseAddress(flow, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(flow, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(flow) else { return nil }
        let w = CVPixelBufferGetWidth(flow), h = CVPixelBufferGetHeight(flow)
        let rowBytes = CVPixelBufferGetBytesPerRow(flow)
        // Buffer rows run top to bottom; Vision y runs bottom to top.
        let x0 = Int(r.minX * CGFloat(w)), x1 = Int(r.maxX * CGFloat(w))
        let y0 = Int((1 - r.maxY) * CGFloat(h)), y1 = Int((1 - r.minY) * CGFloat(h))
        var sum: Float = 0
        var n = 0
        for y in max(0, y0)..<min(h, y1) {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float.self)
            for x in max(0, x0)..<min(w, x1) {
                sum += row[x * 2 + 1]
                n += 1
            }
        }
        return n > 0 ? sum / Float(n) : nil
    }


    #if DEBUG
    /// Appends a line to tmp/drinking-debug.log in the app's sandbox, for tuning detection.
    static func debugLog(_ line: String) {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("drinking-debug.log")
        let stamped = "\(Date().formatted(.dateTime.hour().minute().second())) \(line)\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(Data(stamped.utf8)); try? h.close()
        } else {
            try? Data(stamped.utf8).write(to: url)
        }
    }
    #endif

    /// Builds the classifier input around the person closest to the camera (largest face).
    private func makeFrame(now: Date) -> DrinkingClassifier.Frame {
        var frame = DrinkingClassifier.Frame()

        if let detailed = (faceRequest.results ?? []).max(by: { $0.boundingBox.width < $1.boundingBox.width }),
           let lips = detailed.landmarks?.outerLips, lips.pointCount > 0 {
            let pts = lips.normalizedPoints
            mouthInBox = CGPoint(x: pts.map(\.x).reduce(0, +) / CGFloat(pts.count),
                                 y: pts.map(\.y).reduce(0, +) / CGFloat(pts.count))
        }
        if let face = (faceBoxRequest.results ?? []).max(by: { $0.boundingBox.width < $1.boundingBox.width }) {
            let box = face.boundingBox
            let mouth = CGPoint(x: box.minX + mouthInBox.x * box.width, y: box.minY + mouthInBox.y * box.height)
            lastFace = (mouth, box.width, box, now)
        }
        if let f = lastFace, now.timeIntervalSince(f.at) <= Self.faceMemory {
            frame.mouth = f.mouth
            frame.faceWidth = f.width
        }

        if let body = (bodyRequest.results ?? []).first,
           let joints = try? body.recognizedPoints(.all) {
            func p(_ j: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
                guard let pt = joints[j], pt.confidence > 0.2 else { return nil }
                return pt.location
            }
            frame.nose = p(.nose)
            if let l = p(.leftShoulder), let r = p(.rightShoulder) {
                frame.shoulderWidth = DrinkingClassifier.distance(l, r)
            }
            frame.wrists = [p(.leftWrist), p(.rightWrist)].compactMap { $0 }
        }

        for hand in handRequest.results ?? [] {
            if let pts = try? hand.recognizedPoints(.all) {
                frame.handPoints += pts.values.filter { $0.confidence > 0.15 }.map(\.location)
            }
        }
        return frame
    }
}
