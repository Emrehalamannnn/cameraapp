//
//  ReferenceFraming.swift
//  CameraApp
//
//  Framing a shot to match a reference photo.
//
//  The insight that keeps this simple: every composition rule in the app is
//  already expressed as "how far is the subject from where it should be". The
//  default answer for "where it should be" is centred, with the mode's scale
//  and headroom bands. A reference photo simply supplies a different answer.
//
//  So reference mode is not a parallel guidance system — it is the same rules
//  aimed at a different target, which means it inherits the dead zones,
//  hysteresis and dwell behaviour for free.
//
//  The reference is analysed on device. The photo is read through the system
//  picker, which hands over one image without the app ever gaining access to
//  the library.
//

import CoreGraphics
import Foundation
import Vision

/// Where the subject should sit. All values in normalised preview space.
struct CompositionTarget: Sendable, Equatable {
    /// Desired subject offset from centre, `-1...1`. Zero is centred.
    var horizontalOffset: Double = 0
    /// Desired subject height as a fraction of frame height. `nil` keeps the
    /// mode's own scale band.
    var subjectFill: Double?
    /// Desired space above the subject. `nil` keeps the mode's headroom band.
    var headroom: Double?

    /// The default: centred, with the mode deciding scale and headroom.
    static let neutral = CompositionTarget()

    var isNeutral: Bool { self == .neutral }
}

/// A reference photo reduced to the numbers that describe its framing.
struct ReferenceFraming: Sendable, Equatable {
    var target: CompositionTarget
    /// True when a face was found. Without one there is no subject to match,
    /// and the app says so rather than pretending.
    var hasSubject: Bool

    static let none = ReferenceFraming(target: .neutral, hasSubject: false)
}

enum ReferenceFramingExtractor {

    /// Reads the framing out of a reference image.
    ///
    /// Uses the same geometry as the live path — subject box from the union of
    /// faces, offset from centre, fill as box height, headroom above — so the
    /// target is directly comparable to what the camera measures.
    static func extract(from image: CGImage) -> ReferenceFraming {
        let request = VNDetectFaceRectanglesRequest()
        request.revision = VNDetectFaceRectanglesRequestRevision3
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return .none
        }

        let boxes = (request.results ?? []).map(\.boundingBox)
        guard let first = boxes.first else { return .none }
        let box = boxes.dropFirst().reduce(first) { $0.union($1) }
        guard box.width > 0, box.height > 0 else { return .none }

        return ReferenceFraming(
            target: CompositionTarget(
                horizontalOffset: Double(box.midX - 0.5) * 2,
                subjectFill: Double(box.height),
                headroom: max(0, min(1, Double(1 - box.maxY)))
            ),
            hasSubject: true
        )
    }
}

enum ReferenceMatcher {

    /// How close a live measurement has to get before it counts as matching the
    /// reference. Wider than the centring tolerance because matching someone
    /// else's framing exactly is neither possible nor the point.
    static let fillTolerance = 0.06
    static let headroomTolerance = 0.08

    /// Whether the subject scale matches the reference closely enough.
    static func matchesFill(_ fill: Double, target: CompositionTarget) -> Bool {
        guard let desired = target.subjectFill else { return true }
        return abs(fill - desired) <= fillTolerance
    }

    /// Whether the headroom matches the reference closely enough.
    static func matchesHeadroom(_ headroom: Double, target: CompositionTarget) -> Bool {
        guard let desired = target.headroom else { return true }
        return abs(headroom - desired) <= headroomTolerance
    }

    /// The scale correction needed to match the reference, if any.
    ///
    /// - Returns: `.subjectTooFar` when the live subject is smaller than the
    ///   reference (move closer), `.subjectTooClose` when it is larger.
    static func scaleCorrection(
        fill: Double,
        target: CompositionTarget
    ) -> CompositionState? {
        guard let desired = target.subjectFill else { return nil }
        if fill < desired - fillTolerance { return .subjectTooFar }
        if fill > desired + fillTolerance { return .subjectTooClose }
        return nil
    }

    /// The vertical correction needed to match the reference, if any.
    static func headroomCorrection(
        headroom: Double,
        target: CompositionTarget
    ) -> CompositionState? {
        guard let desired = target.headroom else { return nil }
        if headroom > desired + headroomTolerance { return .excessiveHeadroom }
        if headroom < desired - headroomTolerance { return .insufficientHeadroom }
        return nil
    }
}
