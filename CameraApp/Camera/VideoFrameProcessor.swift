//
//  VideoFrameProcessor.swift
//  CameraApp
//
//  Receives every video frame and decides which few reach the analyser.
//
//  Two throttles protect the preview:
//   * a minimum interval between analyses (default 12 Hz), and
//   * a busy flag, so a slow frame can never queue work behind itself.
//
//  Frames the analyser does not take are dropped immediately on the capture
//  queue. The buffer that *is* taken is passed by reference — the CVPixelBuffer
//  is retained for the duration of the analysis, never copied.
//

import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import ImageIO
import QuartzCore

final class VideoFrameProcessor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    /// Serial queue that AVFoundation delivers sample buffers on, and the only
    /// queue that touches this object's mutable state.
    let queue = DispatchQueue(label: "com.cameraapp.video-frames", qos: .userInitiated)

    private let analyzer: FrameAnalysisService
    private let minimumInterval: CFTimeInterval

    private var lastDispatchTime: CFTimeInterval = 0
    private var isAnalyzing = false
    private var isEnabled = false
    private var device: AVCaptureDevice?
    private var orientation: CGImagePropertyOrientation = .right
    private var isMirrored = false
    private var currentRotationAngle: CGFloat = 90

    init(analyzer: FrameAnalysisService, analysesPerSecond: Double = 12) {
        self.analyzer = analyzer
        self.minimumInterval = analysesPerSecond > 0 ? 1.0 / analysesPerSecond : 0
        super.init()
    }

    // MARK: - Configuration (safe from any thread)

    func setEnabled(_ enabled: Bool) {
        queue.async { [self] in
            isEnabled = enabled
            if !enabled { isAnalyzing = false }
        }
    }

    func updateSource(device: AVCaptureDevice?, isMirrored: Bool) {
        queue.async { [self] in
            self.device = device
            self.isMirrored = isMirrored
            self.orientation = Self.imageOrientation(
                previewRotationAngle: currentRotationAngle,
                isMirrored: isMirrored
            )
        }
    }

    /// The rotation angle AVFoundation applies to the preview, in degrees.
    /// Frames are *not* rotated — telling Vision how to read them instead keeps
    /// the pipeline copy-free.
    func updatePreviewRotationAngle(_ angle: CGFloat) {
        queue.async { [self] in
            currentRotationAngle = angle
            orientation = Self.imageOrientation(previewRotationAngle: angle, isMirrored: isMirrored)
        }
    }

    // MARK: - Sample buffer delegate

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard isEnabled, !isAnalyzing else { return }

        let now = CACurrentMediaTime()
        guard now - lastDispatchTime >= minimumInterval else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        lastDispatchTime = now
        isAnalyzing = true

        let context = FrameContext(
            orientation: orientation,
            isMirrored: isMirrored,
            exposure: currentExposure(),
            timestamp: now
        )

        let analyzer = self.analyzer
        Task.detached(priority: .userInitiated) { [weak self] in
            await analyzer.analyze(pixelBuffer: pixelBuffer, context: context)
            self?.queue.async { self?.isAnalyzing = false }
        }
    }

    // MARK: - Helpers

    private func currentExposure() -> ExposureReading? {
        guard let device else { return nil }
        let duration = CMTimeGetSeconds(device.exposureDuration)
        guard duration.isFinite, duration > 0 else { return nil }
        return ExposureReading(
            iso: Double(device.iso),
            duration: duration,
            aperture: Double(device.lensAperture)
        )
    }

    /// Maps the preview's rotation angle onto the EXIF orientation Vision needs
    /// so that detections come back in the same space the user is looking at.
    static func imageOrientation(
        previewRotationAngle angle: CGFloat,
        isMirrored: Bool
    ) -> CGImagePropertyOrientation {
        switch Int(angle.rounded()) % 360 {
        case 0:
            return isMirrored ? .upMirrored : .up
        case 180:
            return isMirrored ? .downMirrored : .down
        case 270:
            return isMirrored ? .rightMirrored : .left
        default: // 90 — portrait, the orientation this app is locked to
            return isMirrored ? .leftMirrored : .right
        }
    }
}
