//
//  AnalysisTypes.swift
//  CameraApp
//
//  The vocabulary shared between the frame-analysis pipeline and the UI.
//  Everything in this file is a value type with no AVFoundation/Vision
//  dependency, so it can be unit tested and reused by future AI modules.
//

import CoreGraphics
import Foundation
import ImageIO

// MARK: - Lighting

/// A coarse judgement about the light available to the camera.
enum LightingQuality: Sendable, Equatable {
    case tooDark
    case dim
    case good
    case overexposed

    /// Whether the scene is lit well enough to take a keeper.
    var isAcceptable: Bool { self == .good }
}

/// The result of evaluating the exposure state of a single frame.
struct LightingAssessment: Sendable, Equatable {
    var quality: LightingQuality
    /// An EV100-style estimate derived from the device's own exposure state.
    /// `nil` when the device did not report usable exposure values.
    var exposureValue: Double?
    /// Average scene luma in `0...1`, sampled sparsely from the luma plane.
    var meanLuma: Double

    static let unknown = LightingAssessment(quality: .good, exposureValue: nil, meanLuma: 0.5)
}

// MARK: - Stability

/// How steady the device is being held.
enum StabilityLevel: Sendable, Equatable {
    case steady
    case slightMotion
    case unsteady

    var isAcceptable: Bool { self == .steady }
}

struct StabilityAssessment: Sendable, Equatable {
    var level: StabilityLevel
    /// Normalised motion energy. `0` is perfectly still; values above ~0.3 are
    /// hand shake severe enough to soften a photo.
    var motionScore: Double

    static let unknown = StabilityAssessment(level: .steady, motionScore: 0)
}

/// A single motion sample from the device's inertial sensors.
struct MotionReading: Sendable, Equatable {
    /// Smoothed magnitude of the gyroscope rotation rate, in radians/second.
    var rotationRate: Double
    /// Smoothed magnitude of user acceleration, in G.
    var userAcceleration: Double
}

// MARK: - Faces

/// A face located in the live feed.
///
/// `boundingBox` uses Vision's convention: normalised `0...1` coordinates with
/// the origin in the **bottom-left**, expressed in the *upright, as-displayed*
/// image space (mirrored for the front camera, matching the preview).
struct DetectedFace: Sendable, Equatable, Identifiable {
    var id: Int
    var boundingBox: CGRect
    var roll: Double?
    var yaw: Double?

    var area: Double { Double(boundingBox.width * boundingBox.height) }
}

// MARK: - Composition

/// Which way the photographer should nudge the frame.
enum HorizontalNudge: Sendable, Equatable {
    case left
    case right

    var inverted: HorizontalNudge { self == .left ? .right : .left }
}

enum CompositionState: Sendable, Equatable {
    /// No subject detected; framing cannot be judged from faces alone.
    case noSubject
    case subjectTooClose
    case subjectTooFar
    case offCenter(HorizontalNudge)
    case balanced

    var isAcceptable: Bool {
        switch self {
        case .balanced, .noSubject: return true
        case .subjectTooClose, .subjectTooFar, .offCenter: return false
        }
    }
}

struct CompositionAssessment: Sendable, Equatable {
    var state: CompositionState
    /// Union of all detected faces, in the same space as `DetectedFace.boundingBox`.
    var subjectBox: CGRect?
    /// Horizontal displacement of the subject from frame centre, in `-1...1`.
    var horizontalOffset: Double
    /// Fraction of the frame height occupied by the subject.
    var subjectFill: Double

    static let noSubject = CompositionAssessment(
        state: .noSubject,
        subjectBox: nil,
        horizontalOffset: 0,
        subjectFill: 0
    )
}

// MARK: - Unified result

/// Everything the pipeline learned from one analysed frame.
///
/// Future modules (aesthetics scoring, pose, gaze, horizon detection…) extend
/// this struct rather than reaching back into AVFoundation.
struct FrameAnalysis: Sendable, Equatable {
    var timestamp: TimeInterval
    var lighting: LightingAssessment
    var stability: StabilityAssessment
    var faces: [DetectedFace]
    var composition: CompositionAssessment
    /// True when the analysed frame is mirrored (front camera), which flips the
    /// meaning of left/right guidance.
    var isMirrored: Bool

    /// The largest detected face, which the guidance logic treats as the subject.
    var primaryFace: DetectedFace? { faces.first }

    static let idle = FrameAnalysis(
        timestamp: 0,
        lighting: .unknown,
        stability: .unknown,
        faces: [],
        composition: .noSubject,
        isMirrored: false
    )
}

// MARK: - Per-frame capture context

/// Immutable per-frame metadata handed to the analyser alongside the pixels.
struct FrameContext: Sendable {
    var orientation: CGImagePropertyOrientation
    var isMirrored: Bool
    var exposure: ExposureReading?
    var timestamp: TimeInterval
}

/// A snapshot of the capture device's exposure state.
struct ExposureReading: Sendable, Equatable {
    /// Sensor sensitivity, e.g. 32…3072.
    var iso: Double
    /// Shutter time in seconds.
    var duration: TimeInterval
    /// Lens f-number.
    var aperture: Double
}
