//
//  StabilityEstimator.swift
//  CameraApp
//
//  Combines inertial data with a cheap frame-difference signal to decide
//  whether the device is being held still enough for a sharp exposure.
//

import Foundation

enum StabilityEstimator {

    static let steadyThreshold = 0.14
    static let slightMotionThreshold = 0.34

    /// Weights chosen so that a typical hand-held rest (~0.03 rad/s) scores
    /// well under `steadyThreshold`, while a deliberate pan (>0.25 rad/s)
    /// or a walking step clears `slightMotionThreshold`.
    static let rotationWeight = 1.8
    static let accelerationWeight = 1.2
    static let frameDeltaWeight = 6.0

    /// - Parameters:
    ///   - motion: inertial reading, or `nil` where Core Motion is unavailable.
    ///   - frameDelta: mean absolute luma change between consecutive analysed
    ///     frames, in `0...1`. Doubles as the fallback motion signal.
    static func evaluate(
        motion: MotionReading?,
        frameDelta: Double,
        configuration: AnalysisConfiguration = .standard
    ) -> StabilityAssessment {
        let steadyThreshold = configuration.steadyThreshold
        let slightMotionThreshold = configuration.slightMotionThreshold
        let clampedDelta = min(max(frameDelta, 0), 1)
        let score: Double
        if let motion {
            // Inertial data is the trustworthy signal; the frame delta only
            // nudges it so that subject motion is not completely ignored.
            score = motion.rotationRate * rotationWeight
                + motion.userAcceleration * accelerationWeight
                + clampedDelta * (frameDeltaWeight * 0.35)
        } else {
            score = clampedDelta * frameDeltaWeight
        }

        let level: StabilityLevel
        if score < steadyThreshold {
            level = .steady
        } else if score < slightMotionThreshold {
            level = .slightMotion
        } else {
            level = .unsteady
        }
        return StabilityAssessment(level: level, motionScore: score)
    }
}
