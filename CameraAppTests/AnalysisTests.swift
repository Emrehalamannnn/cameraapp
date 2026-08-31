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

    private func face(centerX: Double, height: Double, id: Int = 0) -> DetectedFace {
        DetectedFace(
            id: id,
            boundingBox: CGRect(
                x: centerX - height / 2,
                y: 0.5 - height / 2,
                width: height,
                height: height
            ),
            roll: nil,
            yaw: nil
        )
    }
}

final class LightingEstimatorTests: XCTestCase {

    func testSunlightExposurePairScoresHigh() {
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
