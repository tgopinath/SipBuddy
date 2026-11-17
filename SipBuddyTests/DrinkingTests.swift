import XCTest
@testable import SipBuddy

final class DrinkingTests: XCTestCase {
    typealias Frame = DrinkingClassifier.Frame
    let mouth = CGPoint(x: 0.5, y: 0.45)

    func testHandAtMouthIsDrinking() {
        let f = Frame(mouth: mouth, faceWidth: 0.25, handPoints: [CGPoint(x: 0.52, y: 0.40)])
        XCTAssertTrue(DrinkingClassifier.isDrinking(f, vesselSeen: true))
    }

    func testHandDownOnDeskIsNotDrinking() {
        let f = Frame(mouth: mouth, faceWidth: 0.25, handPoints: [CGPoint(x: 0.6, y: 0.05)])
        XCTAssertFalse(DrinkingClassifier.isDrinking(f, vesselSeen: true))
    }

    func testFaceHiddenByGlassUsesNose() {
        // Glass covers the face; body pose still sees nose, shoulders and a raised wrist.
        let f = Frame(nose: CGPoint(x: 0.5, y: 0.55), shoulderWidth: 0.5, wrists: [CGPoint(x: 0.5, y: 0.42)])
        XCTAssertTrue(DrinkingClassifier.isDrinking(f, vesselSeen: true))
    }

    func testPersonFarInBackgroundIgnored() {
        let f = Frame(mouth: mouth, faceWidth: 0.04, handPoints: [CGPoint(x: 0.5, y: 0.45)])
        XCTAssertFalse(DrinkingClassifier.isDrinking(f, vesselSeen: true))
    }

    func testNoPersonNoDrinking() {
        XCTAssertFalse(DrinkingClassifier.isDrinking(Frame(handPoints: [mouth]), vesselSeen: true))
    }

    func testHandAtMouthWithoutBottleIsNotDrinking() {
        // Resting your chin on your hand shouldn't count.
        let f = Frame(mouth: mouth, faceWidth: 0.25, handPoints: [CGPoint(x: 0.52, y: 0.40)])
        XCTAssertFalse(DrinkingClassifier.isDrinking(f, vesselSeen: false))
    }

    func testVesselLabels() {
        XCTAssertEqual(DrinkingClassifier.vesselConfidence([("bottle", 0.4), ("person", 0.9)]), 0.4)
        XCTAssertEqual(DrinkingClassifier.vesselConfidence([("cupcake", 0.8), ("eyeglasses", 0.7)]), 0)
    }

    func testNeedsFiveSips() {
        XCTAssertEqual(DrinkingDetector.requiredSips, 5)
    }
}

final class SipCounterTests: XCTestCase {
    let t0 = Date(timeIntervalSinceReferenceDate: 0)

    /// Feeds frames at 10 fps: `drinking` for `on` seconds, then not drinking for `off` seconds.
    func run(_ c: inout SipCounter, from start: TimeInterval, on: TimeInterval, off: TimeInterval) -> TimeInterval {
        var t = start
        while t < start + on { c.update(drinking: true, at: t0 + t); t += 0.1 }
        while t < start + on + off { c.update(drinking: false, at: t0 + t); t += 0.1 }
        return t
    }

    func testFiveLiftsAreFiveSips() {
        var c = SipCounter()
        var t: TimeInterval = 0
        for _ in 0..<5 { t = run(&c, from: t, on: 1.0, off: 2.0) }
        XCTAssertEqual(c.total(at: t0 + t), 5)
    }

    func testQuickTouchIsNotASip() {
        var c = SipCounter()
        let t = run(&c, from: 0, on: 0.3, off: 2.0)
        XCTAssertEqual(c.total(at: t0 + t), 0)
    }

    func testLongGulpCountsSeveralSips() {
        var c = SipCounter()
        let t = run(&c, from: 0, on: 6.2, off: 1.0)   // steady drinking ≈ 4 swallows
        XCTAssertEqual(c.total(at: t0 + t), 4)
    }

    func testFourSipsDoNotClose() {
        var c = SipCounter()
        var t: TimeInterval = 0
        for _ in 0..<4 { t = run(&c, from: t, on: 1.0, off: 2.0) }
        XCTAssertLessThan(c.total(at: t0 + t), DrinkingDetector.requiredSips)
    }

    func testThroatSwallowsReplaceTheEstimate() {
        var c = SipCounter()
        c.update(drinking: true, at: t0)
        for i in 1...3 {                       // three swallows seen during a 1 s lift
            c.update(drinking: true, at: t0 + Double(i) * 0.3)
            c.addSwallow()
        }
        _ = run(&c, from: 1.0, on: 0, off: 2.0)
        XCTAssertEqual(c.total(at: t0 + 3), 3)
    }
}

final class SwallowDetectorTests: XCTestCase {
    let t0 = Date(timeIntervalSinceReferenceDate: 0)

    func feed(_ d: inout SwallowDetector, _ samples: [Float]) -> Int {
        var count = 0
        for (i, m) in samples.enumerated() where d.feed(m, at: t0 + Double(i) * 0.1) { count += 1 }
        return count
    }

    func testRiseThenFallIsOneSwallow() {
        var d = SwallowDetector()
        let quiet = [Float](repeating: 0.02, count: 20)
        XCTAssertEqual(feed(&d, quiet + [-0.5, -0.4, 0.0, 0.45, 0.3] + quiet), 1)
    }

    func testJitterIsNotASwallow() {
        var d = SwallowDetector()
        XCTAssertEqual(feed(&d, (0..<60).map { $0 % 2 == 0 ? 0.04 : -0.04 }), 0)
    }

    func testOneWayMovementIsNotASwallow() {
        var d = SwallowDetector()
        XCTAssertEqual(feed(&d, [Float](repeating: 0.02, count: 20) + [0.5, 0.5, 0.5] + [Float](repeating: 0.02, count: 20)), 0)
    }

    func testThreeSwallows() {
        var d = SwallowDetector()
        let quiet = [Float](repeating: 0.02, count: 10)
        let swallow: [Float] = [-0.5, 0.0, 0.5]
        XCTAssertEqual(feed(&d, quiet + swallow + quiet + swallow + quiet + swallow + quiet), 3)
    }
}
