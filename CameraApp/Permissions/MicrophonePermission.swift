//
//  MicrophonePermission.swift
//  CameraApp
//
//  The audio half of `CameraPermission`. Kept as a separate ask, at the point
//  video recording actually needs it, rather than bundled into the camera
//  prompt everyone sees on first launch — most of the app never touches audio.
//

import AVFoundation
import Foundation

enum MicrophonePermission {

    enum Access: Equatable {
        case granted
        case denied
        /// The user has not been asked yet.
        case undetermined
    }

    static var access: Access {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .notDetermined: return .undetermined
        case .denied, .restricted: return .denied
        @unknown default: return .denied
        }
    }

    /// Requests access, prompting only if the user has not been asked before.
    static func requestAccess() async -> Access {
        guard access == .undetermined else { return access }
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        return granted ? .granted : .denied
    }
}
