//
//  ShotQualityModel.swift
//  CameraApp
//
//  One conservative readiness decision assembled from every analysed signal.
//  The numeric score is internal calibration data, never user-facing UI.
//

import Foundation

enum ShotQualityModel {

    static func evaluate(
        lighting: LightingAssessment,
        stability: StabilityAssessment,
        faces: [DetectedFace],
        composition: CompositionAssessment,
        level: LevelAssessment,
        configuration: AnalysisConfiguration = .standard
    ) -> ShotQualityAssessment {
        var score = 100
        var hasCriticalFailure = false
        var hasCorrection = false

        switch lighting.quality {
        case .tooDark:
            score -= 50
            hasCriticalFailure = true
        case .overexposed:
            score -= 40
            hasCriticalFailure = true
        case .dim:
            score -= 24
            hasCorrection = true
        case .good:
            break
        }

        switch stability.level {
        case .unsteady:
            score -= 38
            hasCriticalFailure = true
        case .slightMotion:
            score -= 16
            hasCorrection = true
        case .steady:
            break
        }

        switch composition.state {
        case .dangerousEdge:
            score -= 45
            hasCriticalFailure = true
        case .subjectTooClose, .subjectTooFar:
            score -= 24
            hasCorrection = true
        case .offCenter, .excessiveHeadroom, .insufficientHeadroom:
            score -= 13
            hasCorrection = true
        case .balanced, .noSubject:
            break
        }

        if !level.isAcceptable {
            score -= 12
            hasCorrection = true
        }

        if !faces.isEmpty && composition.detectionConfidence < configuration.minimumDetectionConfidence {
            score -= 20
            hasCorrection = true
        }

        score = min(max(score, 0), 100)
        let severity: ShotQualitySeverity = hasCriticalFailure
            ? .critical
            : (hasCorrection ? .correctable : .good)
        let ready = severity == .good && score >= configuration.readyScore
        return ShotQualityAssessment(score: score, severity: severity, isReady: ready)
    }
}
