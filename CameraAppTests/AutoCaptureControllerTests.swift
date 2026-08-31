//
//  AutoCaptureControllerTests.swift
//  CameraAppTests
//

import XCTest
@testable import CameraApp

final class AutoCaptureControllerTests: XCTestCase {

    func testDoesNotFireBeforeReadyDwell() {
        var controller = makeController()
        XCTAssertFalse(update(&controller, now: 0).shouldCapture)
        XCTAssertFalse(update(&controller, now: 0.69).shouldCapture)
        XCTAssertTrue(update(&controller, now: 0.71).shouldCapture)
    }

    func testStableReadyFiresExactlyOnce() {
        var controller = makeController()
        _ = update(&controller, now: 0)
        XCTAssertTrue(update(&controller, now: 0.8).shouldCapture)
        XCTAssertFalse(update(&controller, now: 1.6).shouldCapture)
        XCTAssertFalse(update(&controller, now: 2.4).shouldCapture)
    }

    func testReadyLossCancelsProgressImmediately() {
        var controller = makeController()
        XCTAssertEqual(update(&controller, now: 0).progress, 0)
        XCTAssertGreaterThan(update(&controller, now: 0.4).progress, 0)
        XCTAssertEqual(
            controller.update(isEnabled: true, isReady: false, canCapture: true, now: 0.41),
            .idle
        )
        XCTAssertFalse(update(&controller, now: 0.8).shouldCapture)
    }

    func testSecondCaptureRequiresLeavingAndReenteringReady() {
        var controller = makeController()
        _ = update(&controller, now: 0)
        XCTAssertTrue(update(&controller, now: 0.8).shouldCapture)
        XCTAssertFalse(update(&controller, now: 2).shouldCapture)

        _ = controller.update(isEnabled: true, isReady: false, canCapture: true, now: 2.1)
        XCTAssertFalse(update(&controller, now: 2.2).shouldCapture)
        XCTAssertTrue(update(&controller, now: 3).shouldCapture)
    }

    func testManualCaptureCancelsPendingAndRequiresReadyExit() {
        var controller = makeController()
        _ = update(&controller, now: 0)
        _ = update(&controller, now: 0.4)
        controller.reset(requiresReadyExit: true)

        XCTAssertFalse(update(&controller, now: 2).shouldCapture)
        _ = controller.update(isEnabled: true, isReady: false, canCapture: true, now: 2.1)
        XCTAssertFalse(update(&controller, now: 2.2).shouldCapture)
        XCTAssertTrue(update(&controller, now: 3).shouldCapture)
    }

    func testCameraSwitchAndBackgroundResetPendingState() {
        var controller = makeController()
        _ = update(&controller, now: 0)
        _ = update(&controller, now: 0.5)
        controller.reset(requiresReadyExit: true)
        XCTAssertEqual(update(&controller, now: 1.5), .idle)

        _ = controller.update(isEnabled: true, isReady: false, canCapture: false, now: 1.6)
        XCTAssertFalse(update(&controller, now: 1.7).shouldCapture)
        XCTAssertTrue(update(&controller, now: 2.5).shouldCapture)
    }

    func testFocusSuppressionStartsAFreshDwellAfterSettling() {
        var controller = makeController()
        controller.suppress(until: 1)
        XCTAssertEqual(update(&controller, now: 0.9), .idle)
        XCTAssertFalse(update(&controller, now: 1).shouldCapture)
        XCTAssertTrue(update(&controller, now: 1.71).shouldCapture)
    }

    func testDisabledAutoCaptureNeverAccumulatesProgress() {
        var controller = makeController()
        XCTAssertEqual(
            controller.update(isEnabled: false, isReady: true, canCapture: true, now: 0),
            .idle
        )
        XCTAssertEqual(
            controller.update(isEnabled: false, isReady: true, canCapture: true, now: 10),
            .idle
        )
    }

    private func makeController() -> AutoCaptureController {
        var configuration = AnalysisConfiguration.standard
        configuration.autoCaptureDwell = 0.7
        return AutoCaptureController(configuration: configuration)
    }

    private func update(
        _ controller: inout AutoCaptureController,
        now: TimeInterval
    ) -> AutoCaptureUpdate {
        controller.update(isEnabled: true, isReady: true, canCapture: true, now: now)
    }
}
