//
//  BodyPoseAnalyzer.swift
//  CameraApp
//
//  Full-body framing, from actual body observations.
//
//  Phase 2 deliberately refused to guess at body crops from face geometry
//  alone. With Vision's body-pose joints there is something real to reason
//  about, so outfit shots can finally be judged on the thing that actually
//  ruins them: where the frame cuts the person off.
//
//  The rule photographers use is that a crop through a joint reads as an
//  accident — knees and ankles especially. Cropping mid-thigh or mid-calf
//  looks deliberate; cropping exactly at the knee looks like a mistake. That
//  is the whole heuristic, and it is applied only when the joints are actually
//  visible with enough confidence to trust.
//
//  The request is only run in modes that ask for it, so portraits and scenes
//  pay nothing for it.
//

import CoreGraphics
import Foundation
import Vision

/// Where the frame is cutting the subject's body.
enum BodyCrop: Sendable, Equatable {
    /// The whole body is in frame.
    case none
    /// Cut across a joint, which reads as an accident.
    case throughJoint(BodyJoint)
    /// Cut below the joints we can see, but cleanly.
    case clean
}

enum BodyJoint: String, Sendable, Equatable {
    case knee
    case ankle
    case hip
}

/// What the pose pass found. Normalised, bottom-left origin, same space as faces.
struct BodyObservation: Sendable, Equatable {
    var boundingBox: CGRect
    var confidence: Double
    /// Lowest confident joint, in normalised frame coordinates.
    var lowestJointY: Double
    var lowestJoint: BodyJoint?
    /// True when both ankles are visible and inside the frame.
    var hasFeetInFrame: Bool

    static let none = BodyObservation(
        boundingBox: .zero,
        confidence: 0,
        lowestJointY: 0,
        lowestJoint: nil,
        hasFeetInFrame: false
    )
}

enum BodyPoseRules {

    /// How close to the bottom edge a joint has to be before the frame counts
    /// as cutting through it.
    static let jointCropMargin = 0.06

    /// Judges where the frame is cutting the body.
    ///
    /// Pure, so the rule can be tested against synthesised joints rather than
    /// needing a person in front of a camera.
    static func crop(for body: BodyObservation, configuration: AnalysisConfiguration) -> BodyCrop {
        guard body.confidence >= Double(configuration.minimumDetectionConfidence) else {
            return .none
        }
        if body.hasFeetInFrame { return .none }
        guard let joint = body.lowestJoint else { return .clean }

        // A joint sitting right on the bottom edge is the accidental-looking
        // crop; one comfortably above it means the cut lands on a limb, which
        // reads as deliberate.
        return body.lowestJointY <= jointCropMargin ? .throughJoint(joint) : .clean
    }
}

/// Runs Vision's body-pose request and reduces it to the few numbers the
/// framing rules need.
final class BodyPoseAnalyzer {

    private let request: VNDetectHumanBodyPoseRequest
    private let minimumJointConfidence: Float = 0.3

    init() {
        request = VNDetectHumanBodyPoseRequest()
    }

    /// - Returns: the most confident body in frame, or `nil` when there is none.
    func analyze(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation
    ) -> BodyObservation? {
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: orientation,
            options: [:]
        )
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let observation = request.results?.max(by: { $0.confidence < $1.confidence }) else {
            return nil
        }
        return Self.reduce(observation, minimumJointConfidence: minimumJointConfidence)
    }

    /// Turns a pile of joints into a bounding box and a crop verdict.
    static func reduce(
        _ observation: VNHumanBodyPoseObservation,
        minimumJointConfidence: Float
    ) -> BodyObservation? {
        guard let points = try? observation.recognizedPoints(.all) else { return nil }
        let confident = points.filter { $0.value.confidence >= minimumJointConfidence }
        guard !confident.isEmpty else { return nil }

        let locations = confident.values.map(\.location)
        let minX = locations.map(\.x).min() ?? 0
        let maxX = locations.map(\.x).max() ?? 0
        let minY = locations.map(\.y).min() ?? 0
        let maxY = locations.map(\.y).max() ?? 0

        let ankles: [VNHumanBodyPoseObservation.JointName] = [.leftAnkle, .rightAnkle]
        let knees: [VNHumanBodyPoseObservation.JointName] = [.leftKnee, .rightKnee]
        let hips: [VNHumanBodyPoseObservation.JointName] = [.leftHip, .rightHip]

        func lowest(_ names: [VNHumanBodyPoseObservation.JointName]) -> Double? {
            let values = names.compactMap { confident[$0]?.location.y }
            return values.min().map(Double.init)
        }

        let ankleY = lowest(ankles)
        let kneeY = lowest(knees)
        let hipY = lowest(hips)

        let lowestJoint: BodyJoint?
        let lowestY: Double
        if let ankleY {
            lowestJoint = .ankle
            lowestY = ankleY
        } else if let kneeY {
            lowestJoint = .knee
            lowestY = kneeY
        } else if let hipY {
            lowestJoint = .hip
            lowestY = hipY
        } else {
            lowestJoint = nil
            lowestY = Double(minY)
        }

        // Feet count as in frame only when both ankles are visible and clear of
        // the bottom edge — one ankle usually means the other is cut off.
        let visibleAnkles = ankles.compactMap { confident[$0]?.location.y }
        let hasFeet = visibleAnkles.count == 2
            && visibleAnkles.allSatisfy { $0 > CGFloat(BodyPoseRules.jointCropMargin) }

        return BodyObservation(
            boundingBox: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY),
            confidence: Double(observation.confidence),
            lowestJointY: lowestY,
            lowestJoint: lowestJoint,
            hasFeetInFrame: hasFeet
        )
    }
}
