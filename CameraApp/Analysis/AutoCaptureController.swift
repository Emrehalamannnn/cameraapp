//
//  AutoCaptureController.swift
//  CameraApp
//
//  Pure state machine for the safety-sensitive part of Auto Capture. It owns
//  no timer and performs no camera work; the analysed-frame clock drives it.
//

import Foundation

struct AutoCaptureUpdate: Sendable, Equatable {
    var progress: Double
    var shouldCapture: Bool

    static let idle = AutoCaptureUpdate(progress: 0, shouldCapture: false)
}

struct AutoCaptureController {
    let dwell: TimeInterval

    private var readySince: TimeInterval?
    private var requiresReadyExit = false
    private var suppressedUntil: TimeInterval = 0

    init(configuration: AnalysisConfiguration = .standard) {
        dwell = configuration.autoCaptureDwell
    }

    mutating func update(
        isEnabled: Bool,
        isReady: Bool,
        canCapture: Bool,
        now: TimeInterval
    ) -> AutoCaptureUpdate {
        guard isEnabled else {
            reset()
            return .idle
        }

        guard isReady else {
            readySince = nil
            requiresReadyExit = false
            return .idle
        }

        guard !requiresReadyExit, canCapture, now >= suppressedUntil else {
            readySince = nil
            return .idle
        }

        guard dwell > 0 else {
            requiresReadyExit = true
            return AutoCaptureUpdate(progress: 1, shouldCapture: true)
        }

        let start = readySince ?? now
        readySince = start
        let progress = min(max((now - start) / dwell, 0), 1)
        guard progress >= 1 else {
            return AutoCaptureUpdate(progress: progress, shouldCapture: false)
        }

        readySince = nil
        requiresReadyExit = true
        return AutoCaptureUpdate(progress: 1, shouldCapture: true)
    }

    /// Cancels a pending dwell. Manual capture, camera switching, and lifecycle
    /// changes latch the controller until Ready has genuinely been left.
    mutating func reset(requiresReadyExit: Bool = false) {
        readySince = nil
        self.requiresReadyExit = requiresReadyExit
        suppressedUntil = 0
    }

    /// Focus/exposure changes may keep the old analysis visually Ready for a
    /// moment. Start a fresh dwell only after the device has had time to settle.
    mutating func suppress(until time: TimeInterval) {
        readySince = nil
        suppressedUntil = max(suppressedUntil, time)
    }
}
