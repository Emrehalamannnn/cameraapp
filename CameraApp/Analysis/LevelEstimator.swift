//
//  LevelEstimator.swift
//  CameraApp
//
//  Converts the gravity vector already sampled for stability into preview roll.
//  No image-based horizon request is needed, so frame-analysis cost is unchanged.
//

import Foundation
import ImageIO

enum LevelEstimator {

    static func evaluate(
        motion: MotionReading?,
        orientation: CGImagePropertyOrientation,
        previous: LevelAssessment? = nil,
        configuration: AnalysisConfiguration = .standard
    ) -> LevelAssessment {
        guard
            let x = motion?.gravityX,
            let y = motion?.gravityY,
            x.isFinite,
            y.isFinite,
            (x * x + y * y).squareRoot() >= 0.5
        else {
            return .unavailable
        }

        let rawRoll: Double
        switch orientation {
        case .right, .rightMirrored:
            rawRoll = atan2(x, -y)
        case .left, .leftMirrored:
            rawRoll = atan2(-x, y)
        case .up, .upMirrored:
            rawRoll = atan2(-y, x)
        case .down, .downMirrored:
            rawRoll = atan2(y, -x)
        @unknown default:
            return .unavailable
        }

        // Negating makes positive values clockwise in the displayed preview.
        let degrees = -rawRoll * 180 / .pi
        let wasTilted = previous?.state == .tiltedClockwise
            || previous?.state == .tiltedCounterclockwise
        let tolerance = wasTilted
            ? configuration.rollExitToleranceDegrees
            : configuration.rollEnterToleranceDegrees

        let state: LevelState
        if abs(degrees) <= tolerance {
            state = .level
        } else {
            state = degrees > 0 ? .tiltedClockwise : .tiltedCounterclockwise
        }
        return LevelAssessment(state: state, rollDegrees: degrees)
    }
}
