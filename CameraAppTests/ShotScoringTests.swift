//
//  ShotScoringTests.swift
//  CameraAppTests
//
//  Best-shot selection has to be right for the reason a human would agree
//  with, so the maths is tested against synthesised images rather than
//  photographs.
//

import XCTest
@testable import CameraApp

final class SharpnessTests: XCTestCase {

    func testFlatImageHasNoDetailToMeasure() {
        let flat = [UInt8](repeating: 128, count: 64 * 64)
        XCTAssertEqual(
            ShotScorer.sharpness(grayPixels: flat, width: 64, height: 64),
            0,
            accuracy: 0.0001
        )
    }

    func testCrispEdgesScoreHigherThanASmearedGradient() {
        let size = 64

        // Hard checkerboard: maximum high-frequency detail.
        var crisp = [UInt8](repeating: 0, count: size * size)
        for y in 0..<size {
            for x in 0..<size {
                crisp[y * size + x] = ((x / 4) + (y / 4)) % 2 == 0 ? 0 : 255
            }
        }

        // Smooth ramp: the same range of tones with the detail smeared out,
        // which is what motion blur does to a frame.
        var blurred = [UInt8](repeating: 0, count: size * size)
        for y in 0..<size {
            for x in 0..<size {
                blurred[y * size + x] = UInt8(min(255, x * 255 / max(1, size - 1)))
            }
        }

        let crispScore = ShotScorer.sharpness(grayPixels: crisp, width: size, height: size)
        let blurredScore = ShotScorer.sharpness(grayPixels: blurred, width: size, height: size)

        XCTAssertGreaterThan(crispScore, blurredScore)
        XCTAssertGreaterThan(crispScore, 0.5)
        XCTAssertLessThan(blurredScore, 0.1)
    }

    func testDegenerateInputIsRejectedRatherThanCrashing() {
        XCTAssertEqual(ShotScorer.sharpness(grayPixels: [], width: 0, height: 0), 0)
        XCTAssertEqual(ShotScorer.sharpness(grayPixels: [1, 2, 3], width: 64, height: 64), 0)
    }
}

final class BestShotSelectorTests: XCTestCase {

    func testEmptyBurstHasNoKeeper() {
        XCTAssertNil(BestShotSelector.best([]))
        XCTAssertTrue(BestShotSelector.rank([]).isEmpty)
    }

    func testSharpestFrameWinsWhenNoFaceIsPresent() {
        let scores = [
            ShotScore(id: 0, sharpness: 0.2, faceQuality: nil),
            ShotScore(id: 1, sharpness: 0.9, faceQuality: nil),
            ShotScore(id: 2, sharpness: 0.5, faceQuality: nil)
        ]
        XCTAssertEqual(BestShotSelector.best(scores)?.id, 1)
    }

    /// The whole point of scoring a burst: a razor-sharp photo of someone
    /// blinking is not the one you want to keep.
    func testFaceQualityOutweighsRawSharpness() {
        let blinking = ShotScore(id: 0, sharpness: 0.95, faceQuality: 0.1)
        let eyesOpen = ShotScore(id: 1, sharpness: 0.6, faceQuality: 0.9)
        XCTAssertEqual(BestShotSelector.best([blinking, eyesOpen])?.id, 1)
    }

    func testRankingIsBestFirstAndRespectsTheLimit() {
        let scores = [
            ShotScore(id: 0, sharpness: 0.3, faceQuality: 0.3),
            ShotScore(id: 1, sharpness: 0.9, faceQuality: 0.9),
            ShotScore(id: 2, sharpness: 0.6, faceQuality: 0.6)
        ]
        let ranked = BestShotSelector.rank(scores, limit: 2)
        XCTAssertEqual(ranked.map(\.id), [1, 2])
    }

    func testTiesKeepTheFrameTheUserActuallyPressedFor() {
        let first = ShotScore(id: 0, sharpness: 0.7, faceQuality: 0.7)
        let second = ShotScore(id: 1, sharpness: 0.7, faceQuality: 0.7)
        XCTAssertEqual(BestShotSelector.best([first, second])?.id, 0)
    }

    func testZeroLimitReturnsNothing() {
        let scores = [ShotScore(id: 0, sharpness: 0.9, faceQuality: 0.9)]
        XCTAssertTrue(BestShotSelector.rank(scores, limit: 0).isEmpty)
    }

    func testOverallFallsBackToSharpnessWithoutAFace() {
        let score = ShotScore(id: 0, sharpness: 0.42, faceQuality: nil)
        XCTAssertEqual(score.overall, 0.42, accuracy: 0.0001)
    }
}
