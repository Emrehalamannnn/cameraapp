//
//  PreviewAndZoomTests.swift
//  CameraAppTests
//
//  Covers the two coordinate/number mappings that are easy to get subtly wrong:
//  aspect-fill preview geometry, and user-facing zoom factors.
//

import CoreGraphics
import ImageIO
import XCTest
@testable import CameraApp

final class PreviewGeometryTests: XCTestCase {

    /// A 4:3 sensor shown on a tall phone screen. The frame is relatively wider
    /// than the screen, so aspect-fill matches the heights and crops the sides.
    private let geometry = PreviewGeometry(
        viewSize: CGSize(width: 390, height: 844),
        contentAspectRatio: 3.0 / 4.0
    )

    func testContentIsAspectFilledAndCroppedHorizontally() {
        let content = geometry.filledContentSize
        XCTAssertEqual(content.height, 844, accuracy: 0.01)
        XCTAssertEqual(content.width, 633, accuracy: 0.01)
    }

    func testFullFrameMapsToTheFilledContentRect() {
        let rect = geometry.rect(forNormalized: CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertEqual(rect.minX, -121.5, accuracy: 0.01, "The frame is cropped evenly on both sides")
        XCTAssertEqual(rect.width, 633, accuracy: 0.01)
        XCTAssertEqual(rect.midY, 422, accuracy: 0.01)
    }

    func testVisionOriginIsFlippedToTheTopLeft() {
        // A box hugging the top of the frame in Vision space (high y).
        let rect = geometry.rect(forNormalized: CGRect(x: 0.4, y: 0.8, width: 0.2, height: 0.2))
        let full = geometry.rect(forNormalized: CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertEqual(rect.minY, full.minY, accuracy: 0.01, "y = 1 in Vision space is the top of the preview")
        XCTAssertEqual(rect.midX, 195, accuracy: 0.01)
    }

    func testInvalidGeometryIsInert() {
        let empty = PreviewGeometry(viewSize: .zero, contentAspectRatio: 0.75)
        XCTAssertFalse(empty.isValid)
        XCTAssertEqual(empty.rect(forNormalized: CGRect(x: 0, y: 0, width: 1, height: 1)), .zero)
    }
}

final class ZoomCapabilitiesTests: XCTestCase {

    /// A dual-wide style device: `videoZoomFactor` 1.0 is the ultra-wide, and
    /// what the user calls "1x" is factor 2.0.
    private let dualWide = ZoomCapabilities(
        baseZoomFactor: 2,
        minimumDisplayFactor: 0.5,
        maximumDisplayFactor: 6,
        displayOptions: [0.5, 1, 2]
    )

    func testUltraWideMapsToDeviceFactorOne() {
        XCTAssertEqual(dualWide.deviceZoomFactor(forDisplayFactor: 0.5), 1, accuracy: 0.0001)
    }

    func testOneTimesMapsToTheSwitchOverFactor() {
        XCTAssertEqual(dualWide.deviceZoomFactor(forDisplayFactor: 1), 2, accuracy: 0.0001)
    }

    func testRequestsAreClampedToTheSupportedRange() {
        XCTAssertEqual(dualWide.deviceZoomFactor(forDisplayFactor: 0.1), 1, accuracy: 0.0001)
        XCTAssertEqual(dualWide.deviceZoomFactor(forDisplayFactor: 99), 12, accuracy: 0.0001)
    }

    func testRoundTripThroughDeviceSpace() {
        XCTAssertEqual(dualWide.displayFactor(forDeviceZoomFactor: 4), 2, accuracy: 0.0001)
    }

    func testSingleLensDeviceIsUnityMapped() {
        XCTAssertEqual(ZoomCapabilities.unity.deviceZoomFactor(forDisplayFactor: 1), 1, accuracy: 0.0001)
    }

    func testLabelsReadLikeACameraApp() {
        XCTAssertEqual(ZoomCapabilities.label(for: 0.5), "0.5×")
        XCTAssertEqual(ZoomCapabilities.label(for: 1), "1×")
        XCTAssertEqual(ZoomCapabilities.label(for: 2), "2×")
        XCTAssertEqual(ZoomCapabilities.label(for: 1.7), "1.7×")
    }
}

final class FrameOrientationTests: XCTestCase {

    func testPortraitRearCameraUsesRightOrientation() {
        XCTAssertEqual(
            VideoFrameProcessor.imageOrientation(previewRotationAngle: 90, isMirrored: false),
            .right
        )
    }

    func testPortraitFrontCameraIsMirrored() {
        XCTAssertEqual(
            VideoFrameProcessor.imageOrientation(previewRotationAngle: 90, isMirrored: true),
            .leftMirrored
        )
    }

    func testLandscapeAnglesAreMapped() {
        XCTAssertEqual(VideoFrameProcessor.imageOrientation(previewRotationAngle: 0, isMirrored: false), .up)
        XCTAssertEqual(VideoFrameProcessor.imageOrientation(previewRotationAngle: 180, isMirrored: false), .down)
        XCTAssertEqual(VideoFrameProcessor.imageOrientation(previewRotationAngle: 270, isMirrored: false), .left)
    }
}
