//
//  EnhancementTests.swift
//  CameraAppTests
//
//  The point of these tests is restraint. Enhancement that overreaches is
//  worse than none at all, so the ceilings are asserted as hard guarantees.
//

import XCTest
@testable import CameraApp

final class ImageStatisticsTests: XCTestCase {

    func testMidGreyFrameMeasuresAsMidGrey() {
        let statistics = ImageStatistics.measure(grayPixels: [UInt8](repeating: 128, count: 1000))
        XCTAssertEqual(statistics.meanLuma, 128.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(statistics.shadowClipping, 0, accuracy: 0.0001)
        XCTAssertEqual(statistics.highlightClipping, 0, accuracy: 0.0001)
    }

    func testCrushedAndBlownPixelsAreCounted() {
        var pixels = [UInt8](repeating: 128, count: 800)
        pixels.append(contentsOf: [UInt8](repeating: 0, count: 100))
        pixels.append(contentsOf: [UInt8](repeating: 255, count: 100))
        let statistics = ImageStatistics.measure(grayPixels: pixels)
        XCTAssertEqual(statistics.shadowClipping, 0.1, accuracy: 0.001)
        XCTAssertEqual(statistics.highlightClipping, 0.1, accuracy: 0.001)
    }

    func testEmptyInputDoesNotDivideByZero() {
        let statistics = ImageStatistics.measure(grayPixels: [])
        XCTAssertEqual(statistics.meanLuma, 0.5, accuracy: 0.0001)
    }
}

final class EnhancementPlannerTests: XCTestCase {

    func testWellExposedPhotoIsLeftAlone() {
        let statistics = ImageStatistics(
            meanLuma: EnhancementPlanner.targetLuma,
            shadowClipping: 0,
            highlightClipping: 0
        )
        let plan = EnhancementPlanner.plan(for: statistics)
        XCTAssertEqual(plan.exposure, 0, accuracy: 0.0001, "A correctly exposed photo needs no exposure change")
        XCTAssertEqual(plan.shadows, 0, accuracy: 0.0001)
        XCTAssertEqual(plan.highlights, 1, accuracy: 0.0001)
    }

    func testDarkPhotoIsLiftedButOnlyPartOfTheWay() {
        let statistics = ImageStatistics(meanLuma: 0.12, shadowClipping: 0.2, highlightClipping: 0)
        let plan = EnhancementPlanner.plan(for: statistics)
        XCTAssertGreaterThan(plan.exposure, 0)
        XCTAssertGreaterThan(plan.shadows, 0)
        // Half a stop is the most it will ever ask for.
        XCTAssertLessThanOrEqual(plan.exposure, EnhancementPlanner.maximumExposure)
    }

    func testBrightPhotoIsPulledBack() {
        let statistics = ImageStatistics(meanLuma: 0.85, shadowClipping: 0, highlightClipping: 0.2)
        let plan = EnhancementPlanner.plan(for: statistics)
        XCTAssertLessThan(plan.exposure, 0)
        XCTAssertLessThan(plan.highlights, 1, "Blown highlights should be recovered")
        XCTAssertGreaterThanOrEqual(plan.exposure, -EnhancementPlanner.maximumExposure)
    }

    /// The guarantee that keeps this from turning faces to plastic: no matter
    /// how badly exposed the input, the adjustments stay inside their ceilings.
    func testEveryPlanStaysInsideItsCeilings() {
        let extremes: [ImageStatistics] = [
            ImageStatistics(meanLuma: 0, shadowClipping: 1, highlightClipping: 0),
            ImageStatistics(meanLuma: 1, shadowClipping: 0, highlightClipping: 1),
            ImageStatistics(meanLuma: 0.5, shadowClipping: 1, highlightClipping: 1),
            ImageStatistics(meanLuma: 0.02, shadowClipping: 0.9, highlightClipping: 0.05)
        ]
        for statistics in extremes {
            let plan = EnhancementPlanner.plan(for: statistics)
            XCTAssertLessThanOrEqual(abs(plan.exposure), EnhancementPlanner.maximumExposure)
            XCTAssertLessThanOrEqual(plan.shadows, EnhancementPlanner.maximumShadowLift)
            XCTAssertGreaterThanOrEqual(
                plan.highlights,
                1 - EnhancementPlanner.maximumHighlightRecovery
            )
            XCTAssertLessThanOrEqual(plan.vibrance, 0.2, "Vibrance must stay subtle")
            XCTAssertLessThanOrEqual(plan.sharpen, 0.4, "Sharpening must stay short of haloing")
        }
    }

    func testAnEmptyPlanIsRecognisedAsDoingNothing() {
        XCTAssertTrue(EnhancementPlan.none.isNoOp)
        XCTAssertFalse(EnhancementPlanner.plan(for: ImageStatistics(
            meanLuma: 0.1,
            shadowClipping: 0.3,
            highlightClipping: 0
        )).isNoOp)
    }
}
