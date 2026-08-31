//
//  DeviceOrientationObserver.swift
//  CameraApp
//
//  The camera UI stays portrait so the preview never jumps, but the controls
//  rotate to meet the user — the behaviour people expect from a camera app.
//

import Foundation
import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class DeviceOrientationObserver {

    private(set) var orientation: UIDeviceOrientation = .portrait

    @ObservationIgnored private var observationTask: Task<Void, Never>?
    @ObservationIgnored private var isObserving = false

    /// Rotation to apply to on-screen controls so they read upright in the hand.
    var controlRotation: Angle {
        switch orientation {
        case .landscapeLeft: return .degrees(90)
        case .landscapeRight: return .degrees(-90)
        case .portraitUpsideDown: return .degrees(180)
        default: return .degrees(0)
        }
    }

    func start() {
        guard !isObserving else { return }
        isObserving = true

        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        update()

        observationTask = Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(
                named: UIDevice.orientationDidChangeNotification
            )
            for await _ in notifications {
                guard let self else { return }
                self.update()
            }
        }
    }

    func stop() {
        guard isObserving else { return }
        isObserving = false
        observationTask?.cancel()
        observationTask = nil
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    private func update() {
        let current = UIDevice.current.orientation
        // Face-up/face-down carry no usable rotation, so the last good value stands.
        guard current.isPortrait || current.isLandscape else { return }
        guard current != orientation else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            orientation = current
        }
    }
}
