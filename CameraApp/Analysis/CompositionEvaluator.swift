//
//  CompositionEvaluator.swift
//  CameraApp
//
//  Judges framing from the detected faces. Pure and synchronous so it can be
//  unit tested and later swapped for a learned model without touching the
//  camera stack.
//

import CoreGraphics
import Foundation

enum CompositionEvaluator {

    /// - Parameters:
    ///   - faces: faces in as-displayed normalised space (bottom-left origin).
    ///   - isMirrored: true for the mirrored front-camera preview. The preview
    ///     behaves like a mirror, so the correction the photographer must make
    ///     is the opposite of the one that centres an unmirrored frame.
    /// Passing the previous assessment gives each threshold a smaller release
    /// boundary than entry boundary. That dead zone prevents a face hovering
    /// on one pixel boundary from alternating instructions every frame.
    static func evaluate(
        faces: [DetectedFace],
        isMirrored: Bool,
        previous: CompositionAssessment? = nil,
        configuration: AnalysisConfiguration = .standard,
        subjectPolicy: SubjectPolicy = .face
    ) -> CompositionAssessment {
        // In scene modes a face in shot is a bystander, not the subject, so
        // face geometry says nothing about whether the frame is well composed.
        // The app would rather stay quiet than invent advice about a plate of
        // food from the position of someone's head behind it.
        guard subjectPolicy == .face else { return .noSubject }

        let reliableFaces = faces.filter { $0.confidence >= configuration.minimumDetectionConfidence }
        guard let first = reliableFaces.first else {
            guard !faces.isEmpty else { return .noSubject }
            var assessment = CompositionAssessment.noSubject
            assessment.detectionConfidence = faces.reduce(Float.zero) { $0 + $1.confidence }
                / Float(faces.count)
            return assessment
        }

        let box = reliableFaces.dropFirst().reduce(first.boundingBox) { $0.union($1.boundingBox) }
        let fill = Double(box.height)
        let offset = Double(box.midX - 0.5) * 2
        let headroom = max(0, min(1, 1 - Double(box.maxY)))
        let edgeClearance = max(
            0,
            min(
                Double(box.minX),
                Double(box.minY),
                1 - Double(box.maxX),
                1 - Double(box.maxY)
            )
        )
        let confidence = reliableFaces.reduce(Float.zero) { $0 + $1.confidence }
            / Float(reliableFaces.count)

        let state: CompositionState
        if edgeClearance < configuration.edgeSafetyMargin {
            state = .dangerousEdge
        } else if fill > maximumFillThreshold(previous: previous, configuration: configuration) {
            state = .subjectTooClose
        } else if fill < minimumFillThreshold(previous: previous, configuration: configuration) {
            state = .subjectTooFar
        } else if headroom < minimumHeadroomThreshold(previous: previous, configuration: configuration) {
            state = .insufficientHeadroom
        } else if headroom > maximumHeadroomThreshold(previous: previous, configuration: configuration) {
            state = .excessiveHeadroom
        } else if abs(offset) > horizontalThreshold(previous: previous, configuration: configuration) {
            // The subject sits left of centre, so the frame has to travel left
            // to catch up with them — unless the preview is mirrored.
            let nudge: HorizontalNudge = offset < 0 ? .left : .right
            state = .offCenter(isMirrored ? nudge.inverted : nudge)
        } else {
            state = .balanced
        }

        return CompositionAssessment(
            state: state,
            subjectBox: box,
            horizontalOffset: offset,
            subjectFill: fill,
            headroom: headroom,
            edgeClearance: edgeClearance,
            detectionConfidence: confidence
        )
    }

    private static func maximumFillThreshold(
        previous: CompositionAssessment?,
        configuration: AnalysisConfiguration
    ) -> Double {
        previous?.state == .subjectTooClose
            ? configuration.maximumSubjectFill - configuration.subjectFillHysteresis
            : configuration.maximumSubjectFill
    }

    private static func minimumFillThreshold(
        previous: CompositionAssessment?,
        configuration: AnalysisConfiguration
    ) -> Double {
        previous?.state == .subjectTooFar
            ? configuration.minimumSubjectFill + configuration.subjectFillHysteresis
            : configuration.minimumSubjectFill
    }

    private static func horizontalThreshold(
        previous: CompositionAssessment?,
        configuration: AnalysisConfiguration
    ) -> Double {
        if case .offCenter? = previous?.state {
            return configuration.horizontalExitTolerance
        }
        return configuration.horizontalEnterTolerance
    }

    private static func minimumHeadroomThreshold(
        previous: CompositionAssessment?,
        configuration: AnalysisConfiguration
    ) -> Double {
        previous?.state == .insufficientHeadroom
            ? configuration.minimumHeadroom + configuration.headroomHysteresis
            : configuration.minimumHeadroom
    }

    private static func maximumHeadroomThreshold(
        previous: CompositionAssessment?,
        configuration: AnalysisConfiguration
    ) -> Double {
        previous?.state == .excessiveHeadroom
            ? configuration.maximumHeadroom - configuration.headroomHysteresis
            : configuration.maximumHeadroom
    }
}
