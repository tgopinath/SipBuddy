import Foundation
import Vision
import CoreImage

/// Remembers the owner's face as a set of Vision feature prints, so only the owner's
/// sips count. Stored locally in Application Support; no photo is kept.
final class OwnerFaceStore: ObservableObject {
    /// Face samples captured while learning.
    static let samplesNeeded = 12

    @Published private(set) var prints: [VNFeaturePrintObservation] = []
    /// Largest distance still treated as the owner, calibrated from the samples.
    @Published private(set) var threshold: Float = 0

    private let fileURL: URL
    private let ciContext = CIContext()
    private let printRequest = VNGenerateImageFeaturePrintRequest()

    var isEnrolled: Bool { prints.count >= Self.samplesNeeded / 2 }

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SipBuddy", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("owner-face.data")
        load()
    }

    // MARK: - Feature prints

    /// A feature print of the face inside `box` (Vision normalized coordinates).
    func featurePrint(of pixelBuffer: CVPixelBuffer, faceBox box: CGRect) -> VNFeaturePrintObservation? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = image.extent
        var rect = CGRect(x: box.minX * extent.width, y: box.minY * extent.height,
                          width: box.width * extent.width, height: box.height * extent.height)
        rect = rect.insetBy(dx: -rect.width * 0.12, dy: -rect.height * 0.12).intersection(extent)
        guard rect.width > 40, rect.height > 40,
              let cg = ciContext.createCGImage(image.cropped(to: rect), from: rect) else { return nil }
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        guard (try? handler.perform([printRequest])) != nil else { return nil }
        return printRequest.results?.first
    }

    /// Smallest distance from `candidate` to any learned sample (lower = more alike).
    func distance(to candidate: VNFeaturePrintObservation) -> Float? {
        prints.compactMap { p -> Float? in
            var d: Float = 0
            return (try? candidate.computeDistance(&d, to: p)) != nil ? d : nil
        }.min()
    }

    func isOwner(_ candidate: VNFeaturePrintObservation) -> Bool {
        guard isEnrolled, let d = distance(to: candidate) else { return false }
        return d <= threshold
    }

    // MARK: - Learning

    func save(samples: [VNFeaturePrintObservation]) {
        prints = samples
        threshold = Self.calibratedThreshold(samples)
        persist()
    }

    func forget() {
        prints = []
        threshold = 0
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Allows a margin above how different the owner's own samples are from each other.
    static func calibratedThreshold(_ samples: [VNFeaturePrintObservation]) -> Float {
        var nearest: [Float] = []
        for (i, a) in samples.enumerated() {
            let others = samples.enumerated().filter { $0.offset != i }.compactMap { _, b -> Float? in
                var d: Float = 0
                return (try? a.computeDistance(&d, to: b)) != nil ? d : nil
            }
            if let m = others.min() { nearest.append(m) }
        }
        guard let worst = nearest.max() else { return 0 }
        return worst * 1.6
    }

    private func persist() {
        let payload: [String: Any] = ["threshold": threshold, "prints": prints]
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: payload, requiringSecureCoding: true) {
            try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? NSKeyedUnarchiver.unarchivedObject(
                ofClasses: [NSDictionary.self, NSArray.self, NSString.self, NSNumber.self, VNFeaturePrintObservation.self],
                from: data) as? [String: Any],
              let saved = payload["prints"] as? [VNFeaturePrintObservation] else { return }
        prints = saved
        threshold = (payload["threshold"] as? NSNumber)?.floatValue ?? 0
    }
}
