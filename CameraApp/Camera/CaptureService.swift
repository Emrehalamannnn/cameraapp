//
//  CaptureService.swift
//  CameraApp
//
//  Owns the AVCaptureSession and everything hanging off it.
//
//  It is an actor, so session configuration, device locking and capture are
//  serialised on a single execution context and never run on the main thread.
//  The session object itself is `nonisolated` because AVCaptureVideoPreviewLayer
//  needs it on the main thread — that reference is read-only for everyone else.
//

import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import UniformTypeIdentifiers

actor CaptureService {

    /// The session backing the preview layer. Safe to read from any thread;
    /// only this actor mutates its configuration.
    nonisolated let session = AVCaptureSession()

    private let photoOutput = AVCapturePhotoOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let frameProcessor: VideoFrameProcessor

    private var activeInput: AVCaptureDeviceInput?
    private var isConfigured = false
    private var zoomCapabilities: ZoomCapabilities = .unity
    private var captureRotationAngle: CGFloat = 90

    init(analyzer: FrameAnalysisService) {
        frameProcessor = VideoFrameProcessor(analyzer: analyzer)
    }

    var currentDevice: AVCaptureDevice? { activeInput?.device }

    var currentDisplayZoom: Double {
        guard let device = currentDevice else { return 1 }
        return zoomCapabilities.displayFactor(forDeviceZoomFactor: Double(device.videoZoomFactor))
    }

    // MARK: - Lifecycle

    /// Configures the session on first call, then starts it.
    @discardableResult
    func start(position: AVCaptureDevice.Position = .back) throws -> CameraConfiguration {
        if !isConfigured {
            try configureSession(position: position)
            isConfigured = true
        }
        if !session.isRunning {
            session.startRunning()
        }
        frameProcessor.setEnabled(true)
        return makeConfiguration()
    }

    func stop() {
        frameProcessor.setEnabled(false)
        if session.isRunning {
            session.stopRunning()
        }
    }

    /// Pauses frame analysis without tearing down the session — used while the
    /// review screen is up, so returning to the camera is instant.
    func setAnalysisEnabled(_ enabled: Bool) {
        frameProcessor.setEnabled(enabled)
    }

    // MARK: - Configuration

    private func configureSession(position: AVCaptureDevice.Position) throws {
        guard let device = DeviceLookup.device(for: position) else {
            throw CameraError.cameraUnavailable
        }

        session.beginConfiguration()
        do {
            session.sessionPreset = .photo

            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { throw CameraError.cannotAddInput }
            session.addInput(input)
            activeInput = input

            guard session.canAddOutput(photoOutput) else { throw CameraError.cannotAddOutput }
            session.addOutput(photoOutput)

            // Late frames are useless for live guidance; drop them rather than
            // building a backlog behind the analyser.
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            guard session.canAddOutput(videoDataOutput) else { throw CameraError.cannotAddOutput }
            session.addOutput(videoDataOutput)
            // `availableVideoPixelFormatTypes` is only populated once the output
            // is attached to the session, so format selection happens here.
            configureVideoDataOutput()
        } catch {
            session.commitConfiguration()
            throw error
        }
        session.commitConfiguration()

        // The preset only picks the device's active format when the change is
        // committed, so anything derived from that format is applied afterwards.
        session.beginConfiguration()
        applyPhotoOutputSettings(for: device)
        session.commitConfiguration()

        applyDefaultDeviceConfiguration(device)
        applyAnalysisMirroring()
        zoomCapabilities = DeviceLookup.zoomCapabilities(for: device)
        applyZoom(displayFactor: 1, ramp: false)
        frameProcessor.updateSource(device: device, isMirrored: device.position == .front)
    }

    private func configureVideoDataOutput() {
        // Prefer the sensor's native bi-planar YUV so no format conversion has
        // to happen for either Vision or the luma sampler.
        let preferredFormats: [OSType] = [
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]
        if let format = preferredFormats.first(where: {
            videoDataOutput.availableVideoPixelFormatTypes.contains($0)
        }) {
            videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: format]
        }
        videoDataOutput.setSampleBufferDelegate(frameProcessor, queue: frameProcessor.queue)
    }

    /// Frames reach the analyser unmirrored, whatever the camera position.
    ///
    /// The preview layer mirrors the front camera on its own; the analyser is
    /// told about that through the Vision orientation instead, so its results
    /// land in the same space the user is looking at. Leaving the data output's
    /// mirroring on "automatic" would make that assumption device-dependent.
    private func applyAnalysisMirroring() {
        guard let connection = videoDataOutput.connection(with: .video),
              connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = false
    }

    private func applyPhotoOutputSettings(for device: AVCaptureDevice) {
        photoOutput.maxPhotoQualityPrioritization = .quality
        if let dimensions = DeviceLookup.maximumPhotoDimensions(for: device) {
            photoOutput.maxPhotoDimensions = dimensions
        }
        // Deferred delivery hands back a low-quality proxy first and finishes
        // the real photo later. Phase 1 wants the finished photo in hand.
        if photoOutput.isAutoDeferredPhotoDeliverySupported {
            photoOutput.isAutoDeferredPhotoDeliveryEnabled = false
        }
    }

    private func applyDefaultDeviceConfiguration(_ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            device.isSubjectAreaChangeMonitoringEnabled = true
        } catch {
            // A device that refuses configuration still previews fine with its
            // defaults, so this is not fatal.
        }
    }

    private func makeConfiguration() -> CameraConfiguration {
        guard let device = currentDevice else { return .unknown }
        return CameraConfiguration(
            isFrontCamera: device.position == .front,
            zoom: zoomCapabilities,
            currentDisplayZoom: currentDisplayZoom,
            isFlashAvailable: device.isFlashAvailable && !photoOutput.supportedFlashModes.isEmpty,
            contentAspectRatio: DeviceLookup.portraitContentAspectRatio(for: device)
        )
    }

    // MARK: - Camera switching

    func switchCamera() throws -> CameraConfiguration {
        guard let existingInput = activeInput else { throw CameraError.notRunning }
        let newPosition: AVCaptureDevice.Position = existingInput.device.position == .back ? .front : .back
        guard let device = DeviceLookup.device(for: newPosition) else {
            throw CameraError.cameraUnavailable
        }

        session.beginConfiguration()
        session.removeInput(existingInput)

        guard let newInput = try? AVCaptureDeviceInput(device: device), session.canAddInput(newInput) else {
            // Put the working camera back rather than leaving a dead session.
            if session.canAddInput(existingInput) {
                session.addInput(existingInput)
            }
            session.commitConfiguration()
            throw CameraError.cannotAddInput
        }

        session.addInput(newInput)
        activeInput = newInput
        session.commitConfiguration()

        session.beginConfiguration()
        applyPhotoOutputSettings(for: device)
        session.commitConfiguration()

        // Connections are rebuilt by the commit, so anything connection-shaped
        // has to be re-applied afterwards.
        applyDefaultDeviceConfiguration(device)
        applyAnalysisMirroring()
        zoomCapabilities = DeviceLookup.zoomCapabilities(for: device)
        applyZoom(displayFactor: 1, ramp: false)
        frameProcessor.updateSource(device: device, isMirrored: device.position == .front)
        applyCaptureRotationAngle()

        return makeConfiguration()
    }

    // MARK: - Zoom

    /// - Returns: the display factor actually applied after clamping.
    @discardableResult
    func applyZoom(displayFactor: Double, ramp: Bool) -> Double {
        guard let device = currentDevice else { return 1 }
        let target = zoomCapabilities.deviceZoomFactor(forDisplayFactor: displayFactor)
        let clamped = min(
            max(CGFloat(target), device.minAvailableVideoZoomFactor),
            device.maxAvailableVideoZoomFactor
        )
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if ramp {
                device.ramp(toVideoZoomFactor: clamped, withRate: 16)
            } else {
                device.cancelVideoZoomRamp()
                device.videoZoomFactor = clamped
            }
        } catch {
            return currentDisplayZoom
        }
        return zoomCapabilities.displayFactor(forDeviceZoomFactor: Double(clamped))
    }

    // MARK: - Focus and exposure

    /// - Parameter devicePoint: point of interest in device space (`0...1`,
    ///   origin top-left of the sensor in landscape-right).
    func focus(at devicePoint: CGPoint, isUserInitiated: Bool) {
        guard let device = currentDevice else { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = devicePoint
            }
            let focusMode: AVCaptureDevice.FocusMode = isUserInitiated ? .autoFocus : .continuousAutoFocus
            if device.isFocusModeSupported(focusMode) {
                device.focusMode = focusMode
            }

            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = devicePoint
            }
            let exposureMode: AVCaptureDevice.ExposureMode = isUserInitiated ? .autoExpose : .continuousAutoExposure
            if device.isExposureModeSupported(exposureMode) {
                device.exposureMode = exposureMode
            }

            // Only watch for subject-area changes after a manual tap, so the
            // camera can fall back to continuous focus when the scene moves on.
            device.isSubjectAreaChangeMonitoringEnabled = isUserInitiated
        } catch {
            // Ignore: focus is best-effort.
        }
    }

    /// Returns focus and exposure to automatic, centred on the frame.
    func resetFocusAndExposure() {
        focus(at: CGPoint(x: 0.5, y: 0.5), isUserInitiated: false)
    }

    // MARK: - Rotation

    /// The angle that keeps captured photos horizon-level, from the device's
    /// physical orientation (see `AVCaptureDevice.RotationCoordinator`).
    func setCaptureRotationAngle(_ angle: CGFloat) {
        captureRotationAngle = angle
        applyCaptureRotationAngle()
    }

    /// The angle AVFoundation uses for the preview, which is also the space the
    /// analysis results are reported in.
    func setPreviewRotationAngle(_ angle: CGFloat) {
        frameProcessor.updatePreviewRotationAngle(angle)
    }

    private func applyCaptureRotationAngle() {
        guard let connection = photoOutput.connection(with: .video) else { return }
        if connection.isVideoRotationAngleSupported(captureRotationAngle) {
            connection.videoRotationAngle = captureRotationAngle
        }
    }

    // MARK: - Capture

    func capturePhoto(flashMode: FlashMode) async throws -> CapturedPhoto {
        guard let device = currentDevice, session.isRunning else {
            throw CameraError.notRunning
        }

        let (settings, contentType) = makePhotoSettings(flashMode: flashMode, device: device)
        applyCaptureRotationAngle()

        let processor = PhotoCaptureProcessor(
            uniformTypeIdentifier: contentType.identifier,
            isMirrored: device.position == .front
        )
        return try await processor.capture(with: settings, using: photoOutput)
    }

    private func makePhotoSettings(
        flashMode: FlashMode,
        device: AVCaptureDevice
    ) -> (AVCapturePhotoSettings, UTType) {
        let settings: AVCapturePhotoSettings
        let contentType: UTType
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc.rawValue])
            contentType = .heic
        } else {
            settings = AVCapturePhotoSettings()
            contentType = .jpeg
        }

        let requestedFlash = flashMode.avFlashMode
        if device.isFlashAvailable, photoOutput.supportedFlashModes.contains(requestedFlash) {
            settings.flashMode = requestedFlash
        } else {
            settings.flashMode = .off
        }

        settings.photoQualityPrioritization = photoOutput.maxPhotoQualityPrioritization
        settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
        return (settings, contentType)
    }
}
