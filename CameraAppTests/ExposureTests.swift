//
//  ExposureTests.swift
//  CameraAppTests
//
//  The exposure readout. A sign that goes the wrong way tells the photographer
//  the opposite of what the camera is doing.
//

import XCTest
@testable import CameraApp

final class ExposureFormatterTests: XCTestCase {

    func testBrighterReadsPositiveAndDarkerReadsNegative() {
        XCTAssertEqual(ExposureFormatter.label(for: 0.7), "+0.7 EV")
        XCTAssertEqual(ExposureFormatter.label(for: -0.7), "-0.7 EV")
    }

    func testZeroStillCarriesItsSign() {
        // "+0.0 EV" is odd on its own, but the chip only appears when there is
        // a correction, and a bare "0.0" would read as a broken value.
        XCTAssertEqual(ExposureFormatter.label(for: 0), "+0.0 EV")
    }

    func testTheReadoutIsRoundedToATenthOfAStop() {
        XCTAssertEqual(ExposureFormatter.label(for: 1.24), "+1.2 EV")
        XCTAssertEqual(ExposureFormatter.label(for: 1.26), "+1.3 EV")
    }

    func testWholeStopsAreNotShownAsIntegers() {
        XCTAssertEqual(ExposureFormatter.label(for: 2), "+2.0 EV")
    }
}
