//
//  AnalysisTypes.swift
//  CameraApp
//
//  The vocabulary shared between the frame-analysis pipeline and the UI.
//  Everything in this file is a value type with no AVFoundation/Vision
//  dependency, so it can be unit tested and reused by future AI modules.
//

import CoreGraphics
import CoreVideo
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
    /// Gravity projected onto the device's screen plane. `nil` when device
    /// attitude is unavailable (including the Simulator).
    var gravityX: Double? = nil
    var gravityY: Double? = nil
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
    var confidence: Float = 1

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
    case dangerousEdge
    case offCenter(HorizontalNudge)
    case excessiveHeadroom
    case insufficientHeadroom
    case balanced

    var isAcceptable: Bool {
        switch self {
        case .balanced, .noSubject: return true
        case .subjectTooClose, .subjectTooFar, .dangerousEdge,
             .offCenter, .excessiveHeadroom, .insufficientHeadroom:
            return false
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
    /// Empty space above the subject in normalised frame coordinates.
    var headroom: Double
    /// Smallest distance between the subject box and any frame edge.
    var edgeClearance: Double
    /// Mean confidence of the faces used to form the assessment.
    var detectionConfidence: Float

    static let noSubject = CompositionAssessment(
        state: .noSubject,
        subjectBox: nil,
        horizontalOffset: 0,
        subjectFill: 0,
        headroom: 0,
        edgeClearance: 1,
        detectionConfidence: 1
    )
}

// MARK: - Level

enum LevelState: Sendable, Equatable {
    case unavailable
    case level
    case tiltedClockwise
    case tiltedCounterclockwise
}

struct LevelAssessment: Sendable, Equatable {
    var state: LevelState
    /// Signed roll in degrees. Positive values are clockwise in preview space.
    var rollDegrees: Double

    var isAcceptable: Bool {
        switch state {
        case .unavailable, .level: return true
        case .tiltedClockwise, .tiltedCounterclockwise: return false
        }
    }

    static let unavailable = LevelAssessment(state: .unavailable, rollDegrees: 0)
}

// MARK: - Shot quality

enum ShotQualitySeverity: Sendable, Equatable {
    case critical
    case correctable
    case good
}

struct ShotQualityAssessment: Sendable, Equatable {
    /// Internal-only quality score. The camera UI deliberately never shows it.
    var score: Int
    var severity: ShotQualitySeverity
    var isReady: Bool

    /// Compatibility default for hand-built analyses. Production analyses are
    /// always assigned an explicit result by `ShotQualityModel`.
    static let unknown = ShotQualityAssessment(score: 100, severity: .good, isReady: true)
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
    var level: LevelAssessment = .unavailable
    var quality: ShotQualityAssessment = .unknown

    /// The largest detected face, which the guidance logic treats as the subject.
    var primaryFace: DetectedFace? { faces.first }

    static let idle = FrameAnalysis(
        timestamp: 0,
        lighting: .unknown,
        stability: .unknown,
        faces: [],
        composition: .noSubject,
        isMirrored: false,
        level: .unavailable,
        quality: .unknown
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

/// One frame handed to the analyser **by reference**.
///
/// `@unchecked Sendable` is a deliberate, load-bearing choice: copying a
/// full-resolution frame per analysis is exactly the cost this pipeline exists
/// to avoid. It is safe because `VideoFrameProcessor` releases at most one
/// frame at a time (its busy flag), the analyser only ever reads the buffer,
/// and AVFoundation does not recycle it while it is retained.
struct FrameSample: @unchecked Sendable {
    var pixelBuffer: CVPixelBuffer
    var context: FrameContext
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
