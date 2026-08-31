//
//  GuidanceEngineTests.swift
//  CameraAppTests
//

import CoreGraphics
import XCTest
@testable import CameraApp

final class GuidanceEngineTests: XCTestCase {

    // MARK: - Priority

    func testDarkSceneOutranksEverythingElse() {
        let analysis = makeAnalysis(
            lighting: .tooDark,
            stability: .unsteady,
            faces: [face(centerX: 0.9, height: 0.2)]
        )
        XCTAssertEqual(GuidanceEngine.target(for: analysis), .moreLight)
    }

    func testMotionOutranksFraming() {
        let analysis = makeAnalysis(
            lighting: .good,
            stability: .unsteady,
            faces: [face(centerX: 0.9, height: 0.2)]
        )
        XCTAssertEqual(GuidanceEngine.target(for: analysis), .holdStill)
    }

    func testTooCloseSubjectAsksForSpace() {
        let analysis = makeAnalysis(
            lighting: .good,
            stability: .steady,
            faces: [face(centerX: 0.5, height: 0.7)]
        )
        XCTAssertEqual(GuidanceEngine.target(for: analysis), .stepBack)
    }

    func testWellFramedSceneIsReady() {
        let analysis = makeAnalysis(
            lighting: .good,
            stability: .steady,
            faces: [face(centerX: 0.5, height: 0.3)]
        )
        XCTAssertEqual(GuidanceEngine.target(for: analysis), .ready)
    }

    func testEmptySceneWithGoodConditionsIsReady() {
        let analysis = makeAnalysis(lighting: .good, stability: .steady, faces: [])
        XCTAssertEqual(GuidanceEngine.target(for: analysis), .ready)
    }

    func testDangerousCropRequestsReframing() {
        let analysis = makeAnalysis(
            lighting: .good,
            stability: .steady,
            faces: [face(centerX: 0.04, height: 0.12)]
        )
        XCTAssertEqual(GuidanceEngine.target(for: analysis), .reframeSubject)
    }

    func testVerticalHeadroomDirectionsMatchPreviewCoordinates() {
        let excessive = makeAnalysis(
            faces: [face(centerX: 0.5, centerY: 0.18, height: 0.2)]
        )
        let insufficient = makeAnalysis(
            faces: [face(centerX: 0.5, centerY: 0.89, height: 0.16)]
        )
        XCTAssertEqual(GuidanceEngine.target(for: excessive), .lowerCamera)
        XCTAssertEqual(GuidanceEngine.target(for: insufficient), .raiseCamera)
    }

    func testLevelCorrectionComesAfterAcceptableFraming() {
        let analysis = makeAnalysis(
            faces: [face(centerX: 0.5, height: 0.3)],
            level: LevelAssessment(state: .tiltedClockwise, rollDegrees: 6)
        )
        XCTAssertEqual(GuidanceEngine.target(for: analysis), .straightenCamera)
    }

    func testFramingCorrectionOutranksLevelCorrection() {
        let analysis = makeAnalysis(
            faces: [face(centerX: 0.2, height: 0.3)],
            level: LevelAssessment(state: .tiltedClockwise, rollDegrees: 6)
        )
        XCTAssertEqual(GuidanceEngine.target(for: analysis), .moveLeft)
    }

    // MARK: - Dwell behaviour

    func testFirstCorrectiveMessageAppearsImmediately() {
        var engine = GuidanceEngine()
        let update = engine.update(with: makeAnalysis(lighting: .tooDark), now: 0)
        XCTAssertEqual(update.state?.message, .moreLight)
        XCTAssertFalse(update.didBecomeReady)
    }

    func testReadyIsNotAnnouncedBeforeItsDwellElapses() {
        var engine = GuidanceEngine()
        let good = makeAnalysis(lighting: .good, stability: .steady, faces: [])

        XCTAssertNil(engine.update(with: good, now: 0).state, "Ready must be earned, not assumed")
        XCTAssertNil(engine.update(with: good, now: 0.3).state)

        let settled = engine.update(with: good, now: 0.65)
        XCTAssertEqual(settled.state?.message, .ready)
        XCTAssertTrue(settled.didBecomeReady)
    }

    func testReadyHapticFiresOnlyOnTheTransition() {
        var engine = GuidanceEngine()
        let good = makeAnalysis(lighting: .good, stability: .steady, faces: [])

        _ = engine.update(with: good, now: 0)
        XCTAssertTrue(engine.update(with: good, now: 0.7).didBecomeReady)

        for tick in 1...10 {
            let update = engine.update(with: good, now: 0.7 + Double(tick) * 0.1)
            XCTAssertEqual(update.state?.message, .ready)
            XCTAssertFalse(update.didBecomeReady, "Ready must not re-fire while it holds")
        }
    }

    func testTransientChangeDoesNotFlipTheMessage() {
        var engine = GuidanceEngine()
        let dark = makeAnalysis(lighting: .tooDark)
        let shaky = makeAnalysis(lighting: .good, stability: .unsteady)

        _ = engine.update(with: dark, now: 0)
        // A single frame of a different condition is not enough to switch.
        XCTAssertEqual(engine.update(with: shaky, now: 0.05).state?.message, .moreLight)
        XCTAssertEqual(engine.update(with: dark, now: 0.1).state?.message, .moreLight)
        XCTAssertEqual(engine.update(with: shaky, now: 0.15).state?.message, .moreLight)
        // Sustained, it is.
        XCTAssertEqual(engine.update(with: shaky, now: 0.6).state?.message, .holdStill)
    }

    func testLeavingReadyIsFasterThanEnteringIt() {
        var engine = GuidanceEngine()
        let good = makeAnalysis(lighting: .good, stability: .steady, faces: [])
        _ = engine.update(with: good, now: 0)
        XCTAssertTrue(engine.update(with: good, now: 1).didBecomeReady)

        let shaky = makeAnalysis(lighting: .good, stability: .unsteady)
        XCTAssertEqual(engine.update(with: shaky, now: 1.05).state?.message, .ready)
        XCTAssertEqual(engine.update(with: shaky, now: 1.35).state?.message, .holdStill)
    }

    func testResetClearsGuidance() {
        var engine = GuidanceEngine()
        _ = engine.update(with: makeAnalysis(lighting: .tooDark), now: 0)
        engine.reset()
        XCTAssertNil(engine.current)
    }

    // MARK: - Helpers

    private func face(centerX: Double, centerY: Double = 0.5, height: Double) -> DetectedFace {
        DetectedFace(
            id: 0,
            boundingBox: CGRect(
                x: centerX - height / 2,
                y: centerY - height / 2,
                width: height,
                height: height
            ),
            roll: nil,
            yaw: nil
        )
    }

    private func makeAnalysis(
        lighting: LightingQuality = .good,
        stability: StabilityLevel = .steady,
        faces: [DetectedFace] = [],
        isMirrored: Bool = false,
        level: LevelAssessment = .unavailable
    ) -> FrameAnalysis {
        let lightingAssessment = LightingAssessment(
            quality: lighting,
            exposureValue: nil,
            meanLuma: 0.5
        )
        let stabilityAssessment = StabilityAssessment(level: stability, motionScore: 0)
        let composition = CompositionEvaluator.evaluate(faces: faces, isMirrored: isMirrored)
        let quality = ShotQualityModel.evaluate(
            lighting: lightingAssessment,
            stability: stabilityAssessment,
            faces: faces,
            composition: composition,
            level: level
        )
        return FrameAnalysis(
            timestamp: 0,
            lighting: lightingAssessment,
            stability: stabilityAssessment,
            faces: faces,
            composition: composition,
            isMirrored: isMirrored,
            level: level,
            quality: quality
        )
    }
}
