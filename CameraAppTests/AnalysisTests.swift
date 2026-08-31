//
//  AnalysisTests.swift
//  CameraAppTests
//
//  Covers the pure signal-processing layer: framing, light, motion.
//

import CoreGraphics
import CoreVideo
import XCTest
@testable import CameraApp

final class CompositionEvaluatorTests: XCTestCase {

    func testNoFacesMeansNoSubject() {
        let assessment = CompositionEvaluator.evaluate(faces: [], isMirrored: false)
        XCTAssertEqual(assessment.state, .noSubject)
        XCTAssertNil(assessment.subjectBox)
    }

    func testCentredSubjectIsBalanced() {
        let assessment = CompositionEvaluator.evaluate(
            faces: [face(centerX: 0.5, height: 0.3)],
            isMirrored: false
        )
        XCTAssertEqual(assessment.state, .balanced)
        XCTAssertEqual(assessment.horizontalOffset, 0, accuracy: 0.0001)
    }

    func testSubjectLeftOfCentreAsksForALeftNudge() {
        let assessment = CompositionEvaluator.evaluate(
            faces: [face(centerX: 0.25, height: 0.3)],
            isMirrored: false
        )
        XCTAssertEqual(assessment.state, .offCenter(.left))
        XCTAssertLessThan(assessment.horizontalOffset, 0)
    }

    func testMirroredPreviewInvertsTheNudge() {
        let assessment = CompositionEvaluator.evaluate(
            faces: [face(centerX: 0.25, height: 0.3)],
            isMirrored: true
        )
        XCTAssertEqual(assessment.state, .offCenter(.right))
    }

    func testCloseSubjectIsTooClose() {
        let assessment = CompositionEvaluator.evaluate(
            faces: [face(centerX: 0.5, height: 0.8)],
            isMirrored: false
        )
        XCTAssertEqual(assessment.state, .subjectTooClose)
    }

    func testDistantSubjectIsTooFar() {
        let assessment = CompositionEvaluator.evaluate(
            faces: [face(centerX: 0.5, height: 0.05)],
            isMirrored: false
        )
        XCTAssertEqual(assessment.state, .subjectTooFar)
    }

    func testGroupIsJudgedAsOneSubject() {
        let assessment = CompositionEvaluator.evaluate(
            faces: [face(centerX: 0.3, height: 0.2), face(centerX: 0.7, height: 0.2, id: 1)],
            isMirrored: false
        )
        XCTAssertEqual(assessment.state, .balanced)
        XCTAssertEqual(assessment.subjectBox?.midX ?? 0, 0.5, accuracy: 0.0001)
    }

    func testExcessiveHeadroomAsksForVerticalCorrection() {
        let assessment = CompositionEvaluator.evaluate(
            faces: [face(centerX: 0.5, centerY: 0.18, height: 0.2)],
            isMirrored: false
        )
        XCTAssertEqual(assessment.state, .excessiveHeadroom)
    }

    func testInsufficientHeadroomAsksForVerticalCorrection() {
        let assessment = CompositionEvaluator.evaluate(
            faces: [face(centerX: 0.5, centerY: 0.92, height: 0.1)],
            isMirrored: false
        )
        XCTAssertEqual(assessment.state, .insufficientHeadroom)
    }

    func testFaceDangerouslyNearEdgeIsCriticalFramingIssue() {
        let assessment = CompositionEvaluator.evaluate(
            faces: [face(centerX: 0.04, height: 0.12)],
            isMirrored: false
        )
        XCTAssertEqual(assessment.state, .dangerousEdge)
        XCTAssertLessThan(assessment.edgeClearance, AnalysisConfiguration.standard.edgeSafetyMargin)
    }

    func testHorizontalDeadZoneMustBeExitedBeforeCorrectionClears() {
        let first = CompositionEvaluator.evaluate(
            faces: [face(centerX: 0.595, height: 0.3)],
            isMirrored: false
        )
        XCTAssertEqual(first.state, .offCenter(.right))

        let stillCorrecting = CompositionEvaluator.evaluate(
            faces: [face(centerX: 0.565, height: 0.3)],
            isMirrored: false,
            previous: first
        )
        XCTAssertEqual(stillCorrecting.state, .offCenter(.right))

        let cleared = CompositionEvaluator.evaluate(
            faces: [face(centerX: 0.55, height: 0.3)],
            isMirrored: false,
            previous: stillCorrecting
        )
        XCTAssertEqual(cleared.state, .balanced)
    }

    func testLowConfidenceFaceDoesNotDriveComposition() {
        let assessment = CompositionEvaluator.evaluate(
            faces: [face(centerX: 0.2, height: 0.3, confidence: 0.2)],
            isMirrored: false
        )
        XCTAssertEqual(assessment.state, .noSubject)
    }

    func testGroupDisplacementUsesUnionRatherThanContradictoryFaces() {
        let assessment = CompositionEvaluator.evaluate(
            faces: [
                face(centerX: 0.15, height: 0.2),
                face(centerX: 0.35, height: 0.2, id: 1)
            ],
            isMirrored: false
        )
        XCTAssertEqual(assessment.state, .offCenter(.left))
    }

    func testSmallGroupAsksPhotographerToMoveCloser() {
        let assessment = CompositionEvaluator.evaluate(
            faces: [
                face(centerX: 0.45, height: 0.05),
                face(centerX: 0.55, height: 0.05, id: 1)
            ],
            isMirrored: false
        )
        XCTAssertEqual(assessment.state, .subjectTooFar)
    }

    private func face(
        centerX: Double,
        centerY: Double = 0.5,
        height: Double,
        id: Int = 0,
        confidence: Float = 1
    ) -> DetectedFace {
        DetectedFace(
            id: id,
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

final class LevelEstimatorTests: XCTestCase {

    func testPortraitGravityWithinToleranceIsLevel() {
        let result = LevelEstimator.evaluate(
            motion: MotionReading(
                rotationRate: 0,
                userAcceleration: 0,
                gravityX: 0,
                gravityY: -1
            ),
            orientation: .right
        )
        XCTAssertEqual(result.state, .level)
        XCTAssertEqual(result.rollDegrees, 0, accuracy: 0.001)
    }

    func testClockwiseAndCounterclockwiseTilt() {
        let clockwise = LevelEstimator.evaluate(
            motion: MotionReading(
                rotationRate: 0,
                userAcceleration: 0,
                gravityX: -0.087,
                gravityY: -0.996
            ),
            orientation: .right
        )
        let counterclockwise = LevelEstimator.evaluate(
            motion: MotionReading(
                rotationRate: 0,
                userAcceleration: 0,
                gravityX: 0.087,
                gravityY: -0.996
            ),
            orientation: .right
        )
        XCTAssertEqual(clockwise.state, .tiltedClockwise)
        XCTAssertEqual(counterclockwise.state, .tiltedCounterclockwise)
    }

    func testLevelHysteresisUsesSmallerReleaseTolerance() {
        let tilted = LevelAssessment(state: .tiltedClockwise, rollDegrees: 5)
        let stillTilted = LevelEstimator.evaluate(
            motion: MotionReading(
                rotationRate: 0,
                userAcceleration: 0,
                gravityX: -0.035,
                gravityY: -0.999
            ),
            orientation: .right,
            previous: tilted
        )
        XCTAssertEqual(stillTilted.state, .tiltedClockwise)

        let level = LevelEstimator.evaluate(
            motion: MotionReading(
                rotationRate: 0,
                userAcceleration: 0,
                gravityX: -0.017,
                gravityY: -0.999
            ),
            orientation: .right,
            previous: stillTilted
        )
        XCTAssertEqual(level.state, .level)
    }

    func testFlatPhoneFailsGracefullyInsteadOfInventingLevel() {
        let result = LevelEstimator.evaluate(
            motion: MotionReading(
                rotationRate: 0,
                userAcceleration: 0,
                gravityX: 0.05,
                gravityY: 0.05
            ),
            orientation: .right
        )
        XCTAssertEqual(result.state, .unavailable)
    }
}

final class ShotQualityModelTests: XCTestCase {

    func testComfortablyGoodShotIsReady() {
        let faces = [face()]
        let composition = CompositionEvaluator.evaluate(faces: faces, isMirrored: false)
        let result = ShotQualityModel.evaluate(
            lighting: LightingAssessment(quality: .good, exposureValue: nil, meanLuma: 0.5),
            stability: StabilityAssessment(level: .steady, motionScore: 0),
            faces: faces,
            composition: composition,
            level: LevelAssessment(state: .level, rollDegrees: 0)
        )
        XCTAssertTrue(result.isReady)
        XCTAssertEqual(result.severity, .good)
    }

    func testDarknessAndDangerousCropAreCritical() {
        let faces = [face(centerX: 0.04)]
        let composition = CompositionEvaluator.evaluate(faces: faces, isMirrored: false)
        let result = ShotQualityModel.evaluate(
            lighting: LightingAssessment(quality: .tooDark, exposureValue: nil, meanLuma: 0.03),
            stability: StabilityAssessment(level: .steady, motionScore: 0),
            faces: faces,
            composition: composition,
            level: .unavailable
        )
        XCTAssertFalse(result.isReady)
        XCTAssertEqual(result.severity, .critical)
        XCTAssertLessThan(result.score, AnalysisConfiguration.standard.readyScore)
    }

    func testTiltIsCorrectableRatherThanCritical() {
        let faces = [face()]
        let composition = CompositionEvaluator.evaluate(faces: faces, isMirrored: false)
        let result = ShotQualityModel.evaluate(
            lighting: LightingAssessment(quality: .good, exposureValue: nil, meanLuma: 0.5),
            stability: StabilityAssessment(level: .steady, motionScore: 0),
            faces: faces,
            composition: composition,
            level: LevelAssessment(state: .tiltedClockwise, rollDegrees: 5)
        )
        XCTAssertFalse(result.isReady)
        XCTAssertEqual(result.severity, .correctable)
    }

    private func face(centerX: Double = 0.5) -> DetectedFace {
        DetectedFace(
            id: 0,
            boundingBox: CGRect(x: centerX - 0.15, y: 0.35, width: 0.3, height: 0.3),
            roll: nil,
            yaw: nil
        )
    }
}

final class LightingEstimatorTests: XCTestCase {

    func testSunlightExposurePairScoresHigh() throws {
        // f/1.8, 1/2000 s, ISO 40 — bright daylight.
        let reading = ExposureReading(iso: 40, duration: 1.0 / 2000, aperture: 1.8)
        let value = try XCTUnwrap(LightingEstimator.exposureValue(for: reading))
        XCTAssertGreaterThan(value, 12)
        XCTAssertEqual(LightingEstimator.evaluate(exposure: reading, meanLuma: 0.5).quality, .good)
    }

    func testDimRoomIsFlagged() {
        // f/1.8, 1/30 s, ISO 800 — a lamp-lit room at night (EV100 ≈ 3.6).
        let reading = ExposureReading(iso: 800, duration: 1.0 / 30, aperture: 1.8)
        XCTAssertEqual(LightingEstimator.evaluate(exposure: reading, meanLuma: 0.45).quality, .dim)
    }

    func testNearDarkSceneIsTooDark() {
        // f/1.8, 1/15 s, ISO 3200 — the sensor is straining (EV100 ≈ 0.6).
        let reading = ExposureReading(iso: 3200, duration: 1.0 / 15, aperture: 1.8)
        XCTAssertEqual(LightingEstimator.evaluate(exposure: reading, meanLuma: 0.4).quality, .tooDark)
    }

    func testMissingExposureFallsBackToLuma() {
        XCTAssertEqual(LightingEstimator.evaluate(exposure: nil, meanLuma: 0.05).quality, .tooDark)
        XCTAssertEqual(LightingEstimator.evaluate(exposure: nil, meanLuma: 0.5).quality, .good)
    }

    func testClippedHighlightsAreOverexposed() {
        let reading = ExposureReading(iso: 40, duration: 1.0 / 2000, aperture: 1.8)
        XCTAssertEqual(LightingEstimator.evaluate(exposure: reading, meanLuma: 0.99).quality, .overexposed)
    }

    func testInvalidExposureIsRejected() {
        XCTAssertNil(LightingEstimator.exposureValue(for: ExposureReading(iso: 0, duration: 0, aperture: 0)))
    }
}

final class StabilityEstimatorTests: XCTestCase {

    func testRestingHandIsSteady() {
        let reading = MotionReading(rotationRate: 0.02, userAcceleration: 0.01)
        XCTAssertEqual(StabilityEstimator.evaluate(motion: reading, frameDelta: 0.002).level, .steady)
    }

    func testPanningIsUnsteady() {
        let reading = MotionReading(rotationRate: 0.4, userAcceleration: 0.2)
        XCTAssertEqual(StabilityEstimator.evaluate(motion: reading, frameDelta: 0.05).level, .unsteady)
    }

    func testFrameDifferenceIsUsedWhenMotionIsUnavailable() {
        XCTAssertEqual(StabilityEstimator.evaluate(motion: nil, frameDelta: 0.001).level, .steady)
        XCTAssertEqual(StabilityEstimator.evaluate(motion: nil, frameDelta: 0.2).level, .unsteady)
    }
}

final class LumaSamplerTests: XCTestCase {

    func testUniformBufferReportsItsBrightness() throws {
        let buffer = try makeBGRABuffer(width: 64, height: 48, gray: 128)
        let sample = try XCTUnwrap(LumaSampler.sample(buffer))
        XCTAssertEqual(sample.mean, 128.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(sample.grid.count, LumaSampler.gridSize * LumaSampler.gridSize)
    }

    func testIdenticalFramesHaveNoDifference() throws {
        let first = try XCTUnwrap(LumaSampler.sample(try makeBGRABuffer(width: 64, height: 48, gray: 90)))
        let second = try XCTUnwrap(LumaSampler.sample(try makeBGRABuffer(width: 64, height: 48, gray: 90)))
        XCTAssertEqual(LumaSampler.difference(first.grid, second.grid), 0, accuracy: 0.0001)
    }

    func testBrightnessChangeShowsUpAsDifference() throws {
        let dark = try XCTUnwrap(LumaSampler.sample(try makeBGRABuffer(width: 64, height: 48, gray: 30)))
        let bright = try XCTUnwrap(LumaSampler.sample(try makeBGRABuffer(width: 64, height: 48, gray: 200)))
        XCTAssertGreaterThan(LumaSampler.difference(dark.grid, bright.grid), 0.5)
    }

    private func makeBGRABuffer(width: Int, height: Int, gray: UInt8) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &buffer
        )
        let pixelBuffer = try XCTUnwrap(buffer)
        XCTAssertEqual(status, kCVReturnSuccess)

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixelBuffer))
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let pointer = base.assumingMemoryBound(to: UInt8.self)
        for row in 0..<height {
            for column in 0..<width {
                let offset = row * bytesPerRow + column * 4
                pointer[offset] = gray       // B
                pointer[offset + 1] = gray   // G
                pointer[offset + 2] = gray   // R
                pointer[offset + 3] = 255    // A
            }
        }
        return pixelBuffer
    }
}
