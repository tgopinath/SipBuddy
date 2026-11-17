import XCTest
import Vision
import AppKit
@testable import SipBuddy

final class OwnerFaceTests: XCTestCase {
    /// Feature print of a simple synthetic picture (a coloured circle on white).
    func print(hue: CGFloat, size: CGFloat = 60) -> VNFeaturePrintObservation {
        let img = NSImage(size: NSSize(width: 160, height: 160), flipped: false) { r in
            NSColor.white.setFill(); r.fill()
            NSColor(hue: hue, saturation: 0.8, brightness: 0.8, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: 80 - size / 2, y: 80 - size / 2, width: size, height: size)).fill()
            return true
        }
        let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let req = VNGenerateImageFeaturePrintRequest()
        try! VNImageRequestHandler(cgImage: cg).perform([req])
        return req.results!.first!
    }

    func testLearnSaveAndReload() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = OwnerFaceStore(directory: dir)
        XCTAssertFalse(store.isEnrolled)
        let samples = (0..<OwnerFaceStore.samplesNeeded).map { print(hue: 0.55, size: 56 + CGFloat($0)) }
        store.save(samples: samples)
        XCTAssertTrue(store.isEnrolled)
        XCTAssertGreaterThan(store.threshold, 0)

        let reloaded = OwnerFaceStore(directory: dir)
        XCTAssertTrue(reloaded.isEnrolled)
        XCTAssertEqual(reloaded.threshold, store.threshold, accuracy: 0.0001)

        // Something like the learned samples matches; something very different doesn't.
        XCTAssertTrue(reloaded.isOwner(print(hue: 0.55, size: 62)))
        XCTAssertFalse(reloaded.isOwner(print(hue: 0.0, size: 130)))

        reloaded.forget()
        XCTAssertFalse(OwnerFaceStore(directory: dir).isEnrolled)
    }
}
