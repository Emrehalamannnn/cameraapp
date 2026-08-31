//
//  GuidanceEngine.swift
//  CameraApp
//
//  Reduces a stream of frame analyses to a single, calm instruction.
//
//  Three rules keep the UI from flickering:
//   * exactly one message is ever visible, chosen by priority;
//   * a candidate message must persist for a dwell period before it replaces
//     the message on screen, and "Ready" has to earn a longer dwell;
//   * nothing is shown at all until the first instruction has been earned.
//

import Foundation

/// The instruction shown to the photographer. Raw values are the display text.
enum GuidanceMessage: String, Sendable, Equatable, CaseIterable {
    case moreLight = "More light needed"
    case tooMuchLight = "Too much light"
    case holdStill = "Hold still"
    case stepBack = "Step back"
    case moveCloser = "Move closer"
    case moveLeft = "Move slightly left"
    case moveRight = "Move slightly right"
    case ready = "Ready"

    var isReady: Bool { self == .ready }
}

struct GuidanceState: Sendable, Equatable {
    var message: GuidanceMessage
    var isReady: Bool { message.isReady }
}

/// The outcome of feeding one analysis to the engine.
struct GuidanceUpdate: Sendable, Equatable {
    /// `nil` while the engine has not yet settled on anything worth saying.
    var state: GuidanceState?
    /// True only on the update where guidance transitions *into* Ready, so the
    /// caller can fire a single haptic instead of buzzing continuously.
    var didBecomeReady: Bool

    static let silent = GuidanceUpdate(state: nil, didBecomeReady: false)
}

struct GuidanceEngine {

    /// How long a new instruction must hold before it is shown.
    var dwell: TimeInterval = 0.35
    /// Ready is a promise, so it has to be earned over a longer window.
    var readyDwell: TimeInterval = 0.6
    /// Leaving Ready is quicker: a shot that stopped being good should stop
    /// claiming to be good.
    var exitReadyDwell: TimeInterval = 0.2

    /// The message currently on screen, or `nil` before the first one is earned.
    private(set) var current: GuidanceMessage?
    private var candidate: GuidanceMessage?
    private var candidateSince: TimeInterval = 0

    init() {}

    /// Priority order: light, then steadiness, then framing. Only one thing is
    /// ever wrong "first", which is what keeps the UI quiet.
    static func target(for analysis: FrameAnalysis) -> GuidanceMessage {
        switch analysis.lighting.quality {
        case .tooDark, .dim:
            return .moreLight
        case .overexposed:
            return .tooMuchLight
        case .good:
            break
        }

        if !analysis.stability.level.isAcceptable {
            return .holdStill
        }

        switch analysis.composition.state {
        case .subjectTooClose:
            return .stepBack
        case .subjectTooFar:
            return .moveCloser
        case .offCenter(let nudge):
            return nudge == .left ? .moveLeft : .moveRight
        case .balanced, .noSubject:
            return .ready
        }
    }

    /// Feeds one analysis to the engine.
    /// - Parameter now: monotonic time in seconds, injected for testability.
    mutating func update(with analysis: FrameAnalysis, now: TimeInterval) -> GuidanceUpdate {
        let target = Self.target(for: analysis)

        // The first corrective instruction appears immediately — telling someone
        // the room is dark should not wait. Ready is always earned.
        if current == nil, !target.isReady {
            current = target
            candidate = nil
            return GuidanceUpdate(state: GuidanceState(message: target), didBecomeReady: false)
        }

        guard target != current else {
            candidate = nil
            return update(holding: current)
        }

        if candidate != target {
            candidate = target
            candidateSince = now
        }

        let requiredDwell: TimeInterval
        if target.isReady {
            requiredDwell = readyDwell
        } else if current?.isReady == true {
            requiredDwell = exitReadyDwell
        } else {
            requiredDwell = dwell
        }

        guard now - candidateSince >= requiredDwell else {
            return update(holding: current)
        }

        let didBecomeReady = target.isReady && current?.isReady != true
        current = target
        candidate = nil
        return GuidanceUpdate(state: GuidanceState(message: target), didBecomeReady: didBecomeReady)
    }

    /// Clears transient state when the feed restarts (camera switch, resume).
    mutating func reset() {
        current = nil
        candidate = nil
        candidateSince = 0
    }

    private func update(holding message: GuidanceMessage?) -> GuidanceUpdate {
        guard let message else { return .silent }
        return GuidanceUpdate(state: GuidanceState(message: message), didBecomeReady: false)
    }
}
