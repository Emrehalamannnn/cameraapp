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

    /// Subject height (as a fraction of frame height) below which the subject
    /// reads as too small to be the point of the photo.
    static let minimumSubjectFill = 0.13
    /// Above this the subject is cropped uncomfortably tight.
    static let maximumSubjectFill = 0.48
    /// Half-width of the "centred enough" band, in `-1...1` offset units.
    static let centerTolerance = 0.16

    /// - Parameters:
    ///   - faces: faces in as-displayed normalised space (bottom-left origin).
    ///   - isMirrored: true for the mirrored front-camera preview. The preview
    ///     behaves like a mirror, so the correction the photographer must make
    ///     is the opposite of the one that centres an unmirrored frame.
    static func evaluate(faces: [DetectedFace], isMirrored: Bool) -> CompositionAssessment {
        guard let first = faces.first else { return .noSubject }

        let box = faces.dropFirst().reduce(first.boundingBox) { $0.union($1.boundingBox) }
        let fill = Double(box.height)
        let offset = Double(box.midX - 0.5) * 2

        let state: CompositionState
        if fill > maximumSubjectFill {
            state = .subjectTooClose
        } else if fill < minimumSubjectFill {
            state = .subjectTooFar
        } else if abs(offset) > centerTolerance {
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
            subjectFill: fill
        )
    }
}
