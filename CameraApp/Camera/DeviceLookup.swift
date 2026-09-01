//
//  DeviceLookup.swift
//  CameraApp
//
//  Picks the best physical camera for a position and describes its zoom range.
//

import AVFoundation
import CoreMedia
import Foundation

enum DeviceLookup {

    /// Preference order matters: virtual devices are chosen first so the system
    /// can switch lenses seamlessly as the zoom factor changes.
    static func device(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let preferredTypes: [AVCaptureDevice.DeviceType]
        switch position {
        case .front:
            preferredTypes = [.builtInTrueDepthCamera, .builtInWideAngleCamera]
        default:
            preferredTypes = [
                .builtInTripleCamera,
                .builtInDualWideCamera,
                .builtInDualCamera,
                .builtInWideAngleCamera
            ]
        }

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: preferredTypes,
            mediaType: .video,
            position: position
        )
        for type in preferredTypes {
            if let match = discovery.devices.first(where: { $0.deviceType == type }) {
                return match
            }
        }
        return discovery.devices.first
    }

    /// Derives the user-facing zoom range for a device.
    static func zoomCapabilities(for device: AVCaptureDevice) -> ZoomCapabilities {
        let switchOverFactors = device.virtualDeviceSwitchOverVideoZoomFactors.map(\.doubleValue)
        let hasUltraWide = device.constituentDevices.contains { $0.deviceType == .builtInUltraWideCamera }

        // With an ultra-wide in the stack, videoZoomFactor 1.0 *is* the 0.5x lens
        // and "1x" lives at the first switch-over point.
        let baseZoomFactor: Double
        if hasUltraWide, let firstSwitchOver = switchOverFactors.first, firstSwitchOver > 1 {
            baseZoomFactor = firstSwitchOver
        } else {
            baseZoomFactor = 1
        }

        let minimumDisplay = Double(device.minAvailableVideoZoomFactor) / baseZoomFactor
        // Digital zoom runs to absurd factors; cap the interactive range at a
        // point where the image is still worth keeping.
        let maximumDisplay = min(Double(device.maxAvailableVideoZoomFactor) / baseZoomFactor, 12)

        var options: [Double] = []
        if minimumDisplay <= 0.55 { options.append(0.5) }
        options.append(1)
        if maximumDisplay >= 2 { options.append(2) }

        return ZoomCapabilities(
            baseZoomFactor: baseZoomFactor,
            minimumDisplayFactor: max(minimumDisplay, 0.5),
            maximumDisplayFactor: max(maximumDisplay, 1),
            displayOptions: options
        )
    }

    /// Width ÷ height of the frames this device produces, as displayed upright
    /// in portrait. A 4:3 sensor reports `0.75`.
    static func portraitContentAspectRatio(for device: AVCaptureDevice) -> Double {
        let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        guard dimensions.width > 0, dimensions.height > 0 else { return 3.0 / 4.0 }
        let shortSide = Double(min(dimensions.width, dimensions.height))
        let longSide = Double(max(dimensions.width, dimensions.height))
        return shortSide / longSide
    }

    /// The largest still-image size the active format can deliver.
    static func maximumPhotoDimensions(for device: AVCaptureDevice) -> CMVideoDimensions? {
        device.activeFormat.supportedMaxPhotoDimensions.max {
            Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height)
        }
    }

    /// The smallest still-image size the active format offers: the sensor's
    /// own output, before any of the larger settings that cost time to
    /// capture and to save.
    ///
    /// Chosen from the supported list rather than computed from the format,
    /// because `maxPhotoDimensions` throws if handed a size the format does
    /// not actually advertise.
    static func nativePhotoDimensions(for device: AVCaptureDevice) -> CMVideoDimensions? {
        device.activeFormat.supportedMaxPhotoDimensions.min {
            Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height)
        }
    }
}
