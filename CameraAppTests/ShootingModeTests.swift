//
//  ShootingModeTests.swift
//  CameraAppTests
//
//  What counts as good framing depends on what is being photographed, so the
//  modes are worth testing as behaviour rather than as a table of constants.
//

import CoreGraphics
import XCTest
@testable import CameraApp

final class ShootingModeTests: XCTestCase {

    // MARK: - Subject policy

    func testSceneModesDoNotJudgeFramingFromFaces() {
        // Someone standing behind a plate of food is not the subject, and the
        // app should not start issuing framing corrections about them.
        let bystander = face(centerX: 0.05, height: 0.3)
        for mode in ShootingMode.allCases where mode.subjectPolicy == .scene {
            let assessment = CompositionEvaluator.evaluate(
                faces: [bystander],
                isMirrored: false,
                configuration: mode.configuration,
                subjectPolicy: mode.subjectPolicy
            )
            XCTAssertEqual(assessment.state, .noSubject, "\(mode.title) should ignore faces")
            XCTAssertNil(assessment.subjectBox, "\(mode.title) should report no subject")
        }
    }

    func testFaceModesStillJudgeFramingFromFaces() {
        for mode in ShootingMode.allCases where mode.subjectPolicy == .face {
            let assessment = CompositionEvaluator.evaluate(
                faces: [face(centerX: 0.05, height: 0.12)],
                isMirrored: false,
                configuration: mode.configuration,
                subjectPolicy: mode.subjectPolicy
            )
            XCTAssertNotEqual(assessment.state, .noSubject, "\(mode.title) should use faces")
        }
    }

    // MARK: - Framing expectations differ by mode

    func testOutfitModeAcceptsTheSmallFaceThatPortraitCallsTooDistant() {
        // A full-body shot puts the face at a fraction of the frame height —
        // exactly what a portrait would complain about.
        let fullBody = [face(centerX: 0.5, centerY: 0.78, height: 0.08)]

        let portrait = CompositionEvaluator.evaluate(
            faces: fullBody,
            isMirrored: false,
            configuration: ShootingMode.portrait.configuration,
            subjectPolicy: ShootingMode.portrait.subjectPolicy
        )
        XCTAssertEqual(portrait.state, .subjectTooFar)

        let outfit = CompositionEvaluator.evaluate(
            faces: fullBody,
            isMirrored: false,
            configuration: ShootingMode.outfit.configuration,
            subjectPolicy: ShootingMode.outfit.subjectPolicy
        )
        XCTAssertEqual(outfit.state, .balanced, "Outfit framing expects a small, high face")
    }

    func testStoryModeWantsRoomAboveTheSubjectForText() {
        // A face pushed high leaves nowhere for the caption. Kept clear of the
        // edge-safety margin so this exercises headroom, not clipping.
        let high = [face(centerX: 0.5, centerY: 0.85, height: 0.16)]
        let story = CompositionEvaluator.evaluate(
            faces: high,
            isMirrored: false,
            configuration: ShootingMode.story.configuration,
            subjectPolicy: ShootingMode.story.subjectPolicy
        )
        XCTAssertEqual(story.state, .insufficientHeadroom)
    }

    // MARK: - Lighting and stability expectations differ by mode

    func testNightModeStopsDemandingLightTheUserChoseNotToHave() {
        // f/1.8, 1/15 s, ISO 3200 — a genuinely dark scene, deliberately shot.
        let reading = ExposureReading(iso: 3200, duration: 1.0 / 15, aperture: 1.8)

        let portrait = LightingEstimator.evaluate(
            exposure: reading,
            meanLuma: 0.3,
            configuration: ShootingMode.portrait.configuration
        )
        XCTAssertEqual(portrait.quality, .tooDark)

        let night = LightingEstimator.evaluate(
            exposure: reading,
            meanLuma: 0.3,
            configuration: ShootingMode.night.configuration
        )
        XCTAssertEqual(night.quality, .good, "Night mode should accept a dark scene")
    }

    func testNightModeDemandsASteadierHandThanPortrait() {
        // A small tremor that a daylight portrait can absorb will smear a long
        // night exposure.
        let tremor = MotionReading(rotationRate: 0.06, userAcceleration: 0.02)

        let portrait = StabilityEstimator.evaluate(
            motion: tremor,
            frameDelta: 0.002,
            configuration: ShootingMode.portrait.configuration
        )
        XCTAssertEqual(portrait.level, .steady)

        let night = StabilityEstimator.evaluate(
            motion: tremor,
            frameDelta: 0.002,
            configuration: ShootingMode.night.configuration
        )
        XCTAssertNotEqual(night.level, .steady, "Night mode should notice the tremor")
    }

    func testLandscapeModeHasTheTightestHorizonTolerance() {
        let landscape = ShootingMode.landscape.configuration.rollEnterToleranceDegrees
        for mode in ShootingMode.allCases where mode != .landscape {
            XCTAssertLessThanOrEqual(
                landscape,
                mode.configuration.rollEnterToleranceDegrees,
                "Landscape should care about the horizon at least as much as \(mode.title)"
            )
        }
    }

    // MARK: - Configuration sanity

    func testEveryModeHasACoherentConfiguration() {
        for mode in ShootingMode.allCases {
            let configuration = mode.configuration
            XCTAssertLessThan(
                configuration.minimumSubjectFill,
                configuration.maximumSubjectFill,
                "\(mode.title) subject scale range is inverted"
            )
            XCTAssertLessThan(
                configuration.minimumHeadroom,
                configuration.maximumHeadroom,
                "\(mode.title) headroom range is inverted"
            )
            XCTAssertLessThan(
                configuration.horizontalExitTolerance,
                configuration.horizontalEnterTolerance,
                "\(mode.title) needs a release tolerance smaller than its entry tolerance"
            )
            XCTAssertLessThan(
                configuration.rollExitToleranceDegrees,
                configuration.rollEnterToleranceDegrees,
                "\(mode.title) needs roll hysteresis"
            )
            XCTAssertGreaterThan(configuration.autoCaptureDwell, 0)
            XCTAssertFalse(mode.shortTitle.isEmpty)
        }
    }

    // MARK: - Helper

    private func face(
        centerX: Double,
        centerY: Double = 0.5,
        height: Double,
        confidence: Float = 1
    ) -> DetectedFace {
        DetectedFace(
            id: 0,
            boundingBox: CGRect(
                x: centerX - height / 2,
                y: centerY - height / 2,
                width: height,
                height: height
            ),
            roll: nil,
            yaw: nil,
            confidence: confidence
        )
    }
}

final class GuidanceDirectionTests: XCTestCase {

    func testSpatialInstructionsCarryAnArrow() {
        XCTAssertEqual(GuidanceMessage.moveLeft.direction, .left)
        XCTAssertEqual(GuidanceMessage.moveRight.direction, .right)
        XCTAssertEqual(GuidanceMessage.raiseCamera.direction, .up)
        XCTAssertEqual(GuidanceMessage.lowerCamera.direction, .down)
        XCTAssertEqual(GuidanceMessage.stepBack.direction, .back)
        XCTAssertEqual(GuidanceMessage.moveCloser.direction, .closer)
    }

    func testNonSpatialInstructionsCarryNoArrow() {
        for message in [GuidanceMessage.moreLight, .tooMuchLight, .holdStill,
                        .reframeSubject, .straightenCamera, .ready] {
            XCTAssertEqual(message.direction, .none, "\(message.rawValue) should not point anywhere")
        }
    }

    /// The arrow must agree with what the user sees, which is the mirrored
    /// image on the front camera.
    func testArrowFollowsTheMirroredPreview() {
        let offLeft = [
            DetectedFace(
                id: 0,
                boundingBox: CGRect(x: 0.1, y: 0.35, width: 0.3, height: 0.3),
                roll: nil,
                yaw: nil,
                confidence: 1
            )
        ]

        let rear = CompositionEvaluator.evaluate(faces: offLeft, isMirrored: false)
        XCTAssertEqual(rear.state, .offCenter(.left))
        XCTAssertEqual(GuidanceMessage.moveLeft.direction, .left)

        let front = CompositionEvaluator.evaluate(faces: offLeft, isMirrored: true)
        XCTAssertEqual(front.state, .offCenter(.right))
        XCTAssertEqual(GuidanceMessage.moveRight.direction, .right)
    }
}
