//
//  CaptureTypes.swift
//  CameraApp
//
//  Value types that let the UI describe what it wants from the camera without
//  importing AVFoundation semantics everywhere.
//

import AVFoundation
import CoreMedia
import Foundation

// MARK: - Flash

enum FlashMode: String, CaseIterable, Sendable, Identifiable {
    case auto
    case on
    case off

    var id: String { rawValue }

    var avFlashMode: AVCaptureDevice.FlashMode {
        switch self {
        case .auto: return .auto
        case .on: return .on
        case .off: return .off
        }
    }

    /// The next mode when the flash button is tapped.
    var next: FlashMode {
        switch self {
        case .auto: return .on
        case .on: return .off
        case .off: return .auto
        }
    }

    var symbolName: String {
        switch self {
        case .auto: return "bolt.badge.automatic.fill"
        case .on: return "bolt.fill"
        case .off: return "bolt.slash.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .auto: return "Flash automatic"
        case .on: return "Flash on"
        case .off: return "Flash off"
        }
    }
}

// MARK: - Zoom

/// Maps between the zoom factors people expect ("0.5x", "1x", "2x") and the
/// `videoZoomFactor` values a device actually takes.
///
/// On a virtual device (dual-wide, triple) `videoZoomFactor == 1` is the
/// *ultra-wide* lens, and the wide lens the user calls "1x" sits at the first
/// switch-over factor. `baseZoomFactor` captures that offset.
struct ZoomCapabilities: Sendable, Equatable {
    var baseZoomFactor: Double
    var minimumDisplayFactor: Double
    var maximumDisplayFactor: Double
    /// Preset factors offered as buttons, e.g. `[0.5, 1, 2]`.
    var displayOptions: [Double]

    static let unity = ZoomCapabilities(
        baseZoomFactor: 1,
        minimumDisplayFactor: 1,
        maximumDisplayFactor: 1,
        displayOptions: [1]
    )

    /// Converts a user-facing factor into a device `videoZoomFactor`, clamped
    /// to what the device supports.
    func deviceZoomFactor(forDisplayFactor factor: Double) -> Double {
        let clamped = min(max(factor, minimumDisplayFactor), maximumDisplayFactor)
        return clamped * baseZoomFactor
    }

    func displayFactor(forDeviceZoomFactor factor: Double) -> Double {
        guard baseZoomFactor > 0 else { return factor }
        return factor / baseZoomFactor
    }

    static func label(for factor: Double) -> String {
        if abs(factor.rounded() - factor) < 0.05 {
            return "\(Int(factor.rounded()))×"
        }
        return String(format: "%.1f×", factor)
    }
}

// MARK: - Session description

/// A snapshot of the running session, handed back to the UI after any change
/// that could alter the controls (start, camera switch).
struct CameraConfiguration: Sendable, Equatable {
    var isFrontCamera: Bool
    var zoom: ZoomCapabilities
    var currentDisplayZoom: Double
    var isFlashAvailable: Bool
    /// Width ÷ height of the preview content as displayed in portrait, e.g.
    /// `0.75` for a 4:3 sensor. Used to map normalised analysis rectangles onto
    /// the aspect-filled preview.
    var contentAspectRatio: Double

    static let unknown = CameraConfiguration(
        isFrontCamera: false,
        zoom: .unity,
        currentDisplayZoom: 1,
        isFlashAvailable: false,
        contentAspectRatio: 3.0 / 4.0
    )
}

// MARK: - Errors

enum CameraError: LocalizedError, Equatable {
    case cameraUnavailable
    case cannotAddInput
    case cannotAddOutput
    case configurationFailed
    case notRunning
    case photoDataUnavailable
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            return "No camera is available on this device."
        case .cannotAddInput, .cannotAddOutput, .configurationFailed:
            return "The camera could not be configured."
        case .notRunning:
            return "The camera is not running."
        case .photoDataUnavailable:
            return "The photo could not be processed."
        case .captureFailed(let reason):
            return reason
        }
    }
}

enum MediaLibraryError: LocalizedError, Equatable {
    case notAuthorized
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "CameraApp needs permission to add photos to your library."
        case .saveFailed(let reason):
            return reason
        }
    }
}
