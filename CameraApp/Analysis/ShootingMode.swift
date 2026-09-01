//
//  ShootingMode.swift
//  CameraApp
//
//  What "well framed" means depends entirely on what you are pointing the
//  camera at. A portrait wants the face high in the frame and reasonably
//  large; an outfit shot wants the same face small and the whole body in;
//  a landscape does not care about faces at all but cares a great deal about
//  the horizon; a night shot must stop nagging about light the photographer
//  has deliberately chosen not to have.
//
//  Rather than bolt special cases onto the composition rules, each mode simply
//  supplies its own calibration and says what it considers the subject to be.
//  The rules themselves stay one implementation.
//

import Foundation

/// What the mode treats as the thing being photographed.
enum SubjectPolicy: Sendable, Equatable {
    /// Framing is judged from faces. No face means nothing to judge.
    case face
    /// Faces are not the subject. Framing advice falls back to what the app can
    /// honestly assess — exposure, steadiness and the horizon — rather than
    /// pretending to understand a plate of food or a product on a table.
    case scene
}

enum ShootingMode: String, CaseIterable, Identifiable, Sendable {
    case portrait
    case outfit
    case food
    case product
    case landscape
    case night
    case story

    var id: String { rawValue }

    var title: String {
        switch self {
        case .portrait: return "Portrait"
        case .outfit: return "Outfit"
        case .food: return "Food"
        case .product: return "Product"
        case .landscape: return "Landscape"
        case .night: return "Night"
        case .story: return "Story"
        }
    }

    /// Short label for the mode strip, which has very little room.
    var shortTitle: String {
        switch self {
        case .portrait: return "PORTRAIT"
        case .outfit: return "OUTFIT"
        case .food: return "FOOD"
        case .product: return "PRODUCT"
        case .landscape: return "SCENE"
        case .night: return "NIGHT"
        case .story: return "STORY"
        }
    }

    var symbolName: String {
        switch self {
        case .portrait: return "person.crop.square"
        case .outfit: return "figure.stand"
        case .food: return "fork.knife"
        case .product: return "cube"
        case .landscape: return "mountain.2"
        case .night: return "moon.stars"
        case .story: return "rectangle.portrait"
        }
    }

    var subjectPolicy: SubjectPolicy {
        switch self {
        case .portrait, .outfit, .story: return .face
        case .food, .product, .landscape, .night: return .scene
        }
    }

    /// Whether the mode runs the body-pose pass. Only full-body framing needs
    /// it, and it is the most expensive thing in the pipeline, so nothing else
    /// pays for it.
    var usesBodyPose: Bool {
        self == .outfit
    }

    /// Modes where a grid genuinely helps are switched on by default.
    var prefersGrid: Bool {
        switch self {
        case .food, .product, .landscape: return true
        case .portrait, .outfit, .night, .story: return false
        }
    }

    /// The calibration this mode shoots with.
    var configuration: AnalysisConfiguration {
        var configuration = AnalysisConfiguration.standard

        switch self {
        case .portrait:
            break // The standard values are tuned for a head-and-shoulders shot.

        case .outfit:
            // Full body: the face is a small part of a tall subject, and it
            // belongs high in the frame with the body below it.
            configuration.minimumSubjectFill = 0.035
            configuration.maximumSubjectFill = 0.16
            configuration.minimumHeadroom = 0.04
            configuration.maximumHeadroom = 0.30
            configuration.horizontalEnterTolerance = 0.14
            configuration.horizontalExitTolerance = 0.09

        case .story:
            // Vertical social crop: subject centred but sitting low enough to
            // leave room for text over the top of the frame.
            configuration.minimumSubjectFill = 0.08
            configuration.maximumSubjectFill = 0.34
            configuration.minimumHeadroom = 0.14
            configuration.maximumHeadroom = 0.45
            configuration.horizontalEnterTolerance = 0.14
            configuration.horizontalExitTolerance = 0.09

        case .food:
            // Usually shot close and often from directly above, where roll is
            // meaningless — the level estimator already stands down when the
            // phone is flat. Steadiness matters more than anything at this range.
            configuration.steadyThreshold = 0.11
            configuration.slightMotionThreshold = 0.26
            configuration.rollEnterToleranceDegrees = 4.0
            configuration.rollExitToleranceDegrees = 2.5

        case .product:
            configuration.steadyThreshold = 0.10
            configuration.slightMotionThreshold = 0.24
            configuration.rollEnterToleranceDegrees = 2.5
            configuration.rollExitToleranceDegrees = 1.5
            configuration.readyScore = 82

        case .landscape:
            // A tilted horizon is the defining error of this mode, so the
            // tolerance is tighter than anywhere else.
            configuration.rollEnterToleranceDegrees = 1.5
            configuration.rollExitToleranceDegrees = 0.8
            configuration.readyScore = 80

        case .night:
            // Long exposures: dark is the point, but any shake ruins the frame.
            configuration.tooDarkExposureValue = -2.5
            configuration.dimExposureValue = 0.5
            configuration.steadyThreshold = 0.07
            configuration.slightMotionThreshold = 0.18
            configuration.autoCaptureDwell = 1.0
            configuration.rollEnterToleranceDegrees = 2.5
            configuration.rollExitToleranceDegrees = 1.5
        }

        return configuration
    }
}
