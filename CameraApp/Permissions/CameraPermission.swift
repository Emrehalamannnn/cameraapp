//
//  CameraPermission.swift
//  CameraApp
//
//  Thin wrapper around the camera authorization dance so the UI layer never
//  has to reason about AVAuthorizationStatus directly.
//

import AVFoundation
import Foundation

enum CameraPermission {

    enum Access: Equatable {
        case granted
        case denied
        /// The user has not been asked yet.
        case undetermined
    }

    static var access: Access {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .granted
        case .notDetermined: return .undetermined
        case .denied, .restricted: return .denied
        @unknown default: return .denied
        }
    }

    /// Requests access, prompting only if the user has not been asked before.
    static func requestAccess() async -> Access {
        guard access == .undetermined else { return access }
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        return granted ? .granted : .denied
    }
}
