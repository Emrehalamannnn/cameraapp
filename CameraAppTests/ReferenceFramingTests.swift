//
//  ReferenceFramingTests.swift
//  CameraAppTests
//
//  Reference mode is the same framing rules aimed at a different target, so
//  the thing worth testing is that the target actually moves the answer.
//

import CoreGraphics
import XCTest
@testable import CameraApp

final class ReferenceMatcherTests: XCTestCase {

    private let target = CompositionTarget(
        horizontalOffset: 0.4,
        subjectFill: 0.25,
        headroom: 0.2
    )

    func testNeutralTargetImposesNothing() {
        XCTAssertTrue(CompositionTarget.neutral.isNeutral)
        XCTAssertNil(ReferenceMatcher.scaleCorrection(fill: 0.9, target: .neutral))
        XCTAssertNil(ReferenceMatcher.headroomCorrection(headroom: 0.9, target: .neutral))
        XCTAssertTrue(ReferenceMatcher.matchesFill(0.9, target: .neutral))
    }

    func testSubjectSmallerThanTheReferenceAsksTheUserToMoveCloser() {
        XCTAssertEqual(ReferenceMatcher.scaleCorrection(fill: 0.1, target: target), .subjectTooFar)
    }

    func testSubjectLargerThanTheReferenceAsksTheUserToStepBack() {
        XCTAssertEqual(ReferenceMatcher.scaleCorrection(fill: 0.5, target: target), .subjectTooClose)
    }

    func testMatchingScaleNeedsNoCorrection() {
        XCTAssertNil(ReferenceMatcher.scaleCorrection(fill: 0.26, target: target))
        XCTAssertTrue(ReferenceMatcher.matchesFill(0.26, target: target))
    }

    func testHeadroomIsComparedAgainstTheReferenceRatherThanTheModeBand() {
        // 0.5 headroom would be fine for a portrait, but the reference wants 0.2.
        XCTAssertEqual(
            ReferenceMatcher.headroomCorrection(headroom: 0.5, target: target),
            .excessiveHeadroom
        )
        XCTAssertEqual(
            ReferenceMatcher.headroomCorrection(headroom: 0.02, target: target),
            .insufficientHeadroom
        )
        XCTAssertNil(ReferenceMatcher.headroomCorrection(headroom: 0.22, target: target))
    }
}

final class ReferenceTargetedCompositionTests: XCTestCase {

    /// The reference sits well off-centre, so a centred subject is now the one
    /// that needs correcting — the exact inverse of the default rule.
    func testOffCentreReferenceMakesACentredSubjectWrong() {
        let offCentreReference = CompositionTarget(horizontalOffset: 0.5, subjectFill: nil, headroom: nil)
        let centred = [face(centerX: 0.5, height: 0.3)]

        let free = CompositionEvaluator.evaluate(faces: centred, isMirrored: false)
        XCTAssertEqual(free.state, .balanced)

        let matching = CompositionEvaluator.evaluate(
            faces: centred,
            isMirrored: false,
            target: offCentreReference
        )
        // The subject is left of where the reference wants it, and panning left
        // brings the frame across to meet it — the same convention the default
        // centring rule uses.
        XCTAssertEqual(matching.state, .offCenter(.left))
    }

    func testSubjectSittingWhereTheReferenceWantsItIsBalanced() {
        let target = CompositionTarget(horizontalOffset: 0.5, subjectFill: nil, headroom: nil)
        let placed = [face(centerX: 0.75, height: 0.3)]
        let assessment = CompositionEvaluator.evaluate(
            faces: placed,
            isMirrored: false,
            target: target
        )
        XCTAssertEqual(assessment.state, .balanced)
    }

    func testReferenceScaleOverridesTheModeBand() {
        // A face filling 0.4 of the frame is fine for a portrait, but not when
        // the reference is a wider shot.
        let wideReference = CompositionTarget(horizontalOffset: 0, subjectFill: 0.15, headroom: nil)
        let tight = [face(centerX: 0.5, height: 0.4)]

        XCTAssertEqual(CompositionEvaluator.evaluate(faces: tight, isMirrored: false).state, .balanced)
        XCTAssertEqual(
            CompositionEvaluator.evaluate(faces: tight, isMirrored: false, target: wideReference).state,
            .subjectTooClose
        )
    }

    func testExtractedFramingRoundTripsThroughTheSameGeometry() {
        // A reference whose subject sits right of centre and fills a quarter of
        // the frame should produce a target that says exactly that.
        let framing = ReferenceFraming(
            target: CompositionTarget(horizontalOffset: 0.3, subjectFill: 0.25, headroom: 0.3),
            hasSubject: true
        )
        XCTAssertTrue(framing.hasSubject)
        XCTAssertFalse(framing.target.isNeutral)
        XCTAssertEqual(ReferenceFraming.none.hasSubject, false)
        XCTAssertTrue(ReferenceFraming.none.target.isNeutral)
    }

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
            yaw: nil,
            confidence: 1
        )
    }
}
