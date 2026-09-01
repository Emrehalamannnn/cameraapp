//
//  AspectCropTests.swift
//  CameraAppTests
//
//  The math behind the app's true 9:16 frame: what gets cropped from a
//  sensor's native aspect ratio, and how the vertical box is sized on a
//  screen that is never assumed to already be 9:16 itself.
//

import CoreGraphics
import XCTest
@testable import CameraApp

final class AspectCropRectTests: XCTestCase {

    func testA4x3SensorIsCroppedOnTheSidesKeepingFullHeight() {
        // 3024×4032 is a typical portrait-displayed 4:3 capture.
        let rect = AspectCrop.rect(for: CGSize(width: 3024, height: 4032))
        XCTAssertEqual(rect.height, 4032, "The narrower axis is never trimmed")
        XCTAssertEqual(rect.width, 2268, accuracy: 1, "4032 * 9/16 == 2268")
        XCTAssertEqual(rect.minX, (3024 - 2268) / 2, accuracy: 1, "Cropped evenly from both sides")
        XCTAssertEqual(rect.minY, 0)
    }

    func testASquareImageIsCroppedOnTheSidesLikeAWiderSensor() {
        // 1:1 is still wider than 9:16 (0.5625), so this takes the same
        // branch as a 4:3 sensor: full height kept, width trimmed.
        let rect = AspectCrop.rect(for: CGSize(width: 1000, height: 1000))
        XCTAssertEqual(rect.height, 1000, "The narrower axis is never trimmed")
        XCTAssertEqual(rect.width, 562.5, accuracy: 1, "1000 * 9/16 == 562.5")
    }

    func testAnImageNarrowerThan9by16IsCroppedTopAndBottom() {
        // Narrower than the target ratio — the one case where the crop keeps
        // the full width and trims height instead.
        let rect = AspectCrop.rect(for: CGSize(width: 500, height: 2000))
        XCTAssertEqual(rect.width, 500, "The narrower axis — width, here — is kept in full")
        XCTAssertEqual(rect.height, 888.89, accuracy: 1, "500 / (9/16) == 888.9")
        XCTAssertEqual(rect.minY, (2000 - rect.height) / 2, accuracy: 1)
    }

    func testAnExactly9by16ImageIsNotCropped() {
        let rect = AspectCrop.rect(for: CGSize(width: 900, height: 1600))
        XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 900, height: 1600))
    }

    func testDegenerateSizesDoNotCrash() {
        XCTAssertEqual(AspectCrop.rect(for: .zero), CGRect(origin: .zero, size: .zero))
        let negativeAspect = AspectCrop.rect(for: CGSize(width: 100, height: 100), targetAspectRatio: 0)
        XCTAssertEqual(negativeAspect, CGRect(x: 0, y: 0, width: 100, height: 100))
    }

    func testTheCropIsAlwaysCentred() {
        let rect = AspectCrop.rect(for: CGSize(width: 4000, height: 3000), targetAspectRatio: 9.0 / 16.0)
        let leftMargin = rect.minX
        let rightMargin = 4000 - rect.maxX
        XCTAssertEqual(leftMargin, rightMargin, accuracy: 1)
    }
}

final class NineSixteenBoxTests: XCTestCase {

    func testAScreenTallerThan9by16LetterboxesTopAndBottom() {
        // iPhone-shaped: 390×844 is far taller than 9:16 (which would be
        // 390×693.3), so the box fills the width and leaves vertical margin.
        let box = CGSize(width: 390, height: 844).nineSixteenBox()
        XCTAssertEqual(box.width, 390, accuracy: 0.01)
        XCTAssertEqual(box.height, 390 * 16.0 / 9.0, accuracy: 0.01)
        XCTAssertEqual(box.midX, 195, accuracy: 0.01)
        XCTAssertLessThan(box.height, 844, "The screen is not assumed to already be 9:16")
    }

    func testTheBoxIsCentredOnBothAxes() {
        let container = CGSize(width: 390, height: 844)
        let box = container.nineSixteenBox()
        XCTAssertEqual(box.minY, (844 - box.height) / 2, accuracy: 0.01)
        XCTAssertEqual(box.minX, 0, accuracy: 0.01, "The box already fills the width on an iPhone-shaped screen")
    }

    func testAWideContainerPillarboxesInstead() {
        // A container wider than it is tall — never happens on this
        // portrait-locked app, but the geometry should not misbehave if it did.
        let box = CGSize(width: 1000, height: 500).nineSixteenBox()
        XCTAssertEqual(box.height, 500, accuracy: 0.01)
        XCTAssertEqual(box.width, 500 * 9.0 / 16.0, accuracy: 0.01)
        XCTAssertLessThan(box.width, 1000)
    }

    func testDegenerateContainerIsInert() {
        XCTAssertEqual(CGSize.zero.nineSixteenBox(), .zero)
    }
}
