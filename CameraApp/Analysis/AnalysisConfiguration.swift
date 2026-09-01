//
//  AnalysisConfiguration.swift
//  CameraApp
//
//  Physical-device calibration lives here. Keeping these values together
//  makes Phase 2.5 tuning possible without hunting through the camera stack.
//

import Foundation

struct AnalysisConfiguration: Sendable, Equatable {
    var minimumDetectionConfidence: Float = 0.5

    var minimumSubjectFill: Double = 0.13
    var maximumSubjectFill: Double = 0.48
    var subjectFillHysteresis: Double = 0.025

    var horizontalEnterTolerance: Double = 0.18
    var horizontalExitTolerance: Double = 0.12

    /// Vision uses a bottom-left origin, so headroom is `1 - box.maxY`.
    /// The upper bound is intentionally conservative until device calibration.
    var minimumHeadroom: Double = 0.035
    var maximumHeadroom: Double = 0.42
    var headroomHysteresis: Double = 0.025

    var edgeSafetyMargin: Double = 0.025

    var rollEnterToleranceDegrees: Double = 3.0
    var rollExitToleranceDegrees: Double = 1.75

    var readyScore: Int = 78
    var guidanceDwell: TimeInterval = 0.35
    var readyDwell: TimeInterval = 0.6
    var exitReadyDwell: TimeInterval = 0.2
    var autoCaptureDwell: TimeInterval = 0.7
    var focusSettlingDwell: TimeInterval = 0.85
    /// How long Ready holds before the instruction fades out of the way.
    var readyFadeDelay: TimeInterval = 1.4

    static let standard = AnalysisConfiguration()
}
