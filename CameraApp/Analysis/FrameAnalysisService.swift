//
//  FrameAnalysisService.swift
//  CameraApp
//
//  The seam where future AI work plugs in.
//
//  It is an actor, so every frame is analysed off the main thread and exactly
//  one at a time; the capture pipeline hands it pixels and reads results back
//  as an `AsyncStream` of `FrameAnalysis` values. Nothing here touches
//  AVCaptureSession, and nothing here touches UIKit.
//

import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import Vision

actor FrameAnalysisService {

    /// Latest analysis results. Buffers only the newest value: if the UI is
    /// busy, stale guidance is worthless and should be dropped rather than queued.
    nonisolated let analyses: AsyncStream<FrameAnalysis>
    private nonisolated let continuation: AsyncStream<FrameAnalysis>.Continuation

    private let faceRequest: VNDetectFaceRectanglesRequest
    private let motionMonitor = MotionMonitor()
    private var configuration: AnalysisConfiguration
    private var subjectPolicy: SubjectPolicy = .face
    private var usesBodyPose = false
    private var compositionTarget: CompositionTarget = .neutral
    /// Built lazily: modes that never ask for pose should not pay to set it up.
    private lazy var bodyPoseAnalyzer = BodyPoseAnalyzer()

    private var previousGrid: [Float]?
    private var previousComposition: CompositionAssessment?
    private var previousLevel: LevelAssessment?
    private var isRunning = false

    init(configuration: AnalysisConfiguration = .standard) {
        let (stream, continuation) = AsyncStream<FrameAnalysis>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        analyses = stream
        self.continuation = continuation
        self.configuration = configuration

        let request = VNDetectFaceRectanglesRequest()
        request.revision = VNDetectFaceRectanglesRequestRevision3
        faceRequest = request
    }

    deinit {
        continuation.finish()
    }

    /// Switches calibration. The mode decides both the thresholds and whether
    /// faces are the subject at all.
    func setMode(_ mode: ShootingMode) {
        configuration = mode.configuration
        subjectPolicy = mode.subjectPolicy
        usesBodyPose = mode.usesBodyPose
        previousComposition = nil
        previousLevel = nil
    }

    /// Aims the framing rules at a reference photo's composition, or back at
    /// the mode's own defaults when cleared.
    func setCompositionTarget(_ target: CompositionTarget) {
        compositionTarget = target
        previousComposition = nil
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        previousGrid = nil
        previousComposition = nil
        previousLevel = nil
        motionMonitor.start()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        previousGrid = nil
        previousComposition = nil
        previousLevel = nil
        motionMonitor.stop()
    }

    /// Analyses one frame and publishes the result.
    ///
    /// The pixel buffer is read in place — locked, sampled, handed to Vision,
    /// released. No image copies, no CIContext, no CGImage round-trip.
    func analyze(_ frame: FrameSample) {
        guard isRunning else { return }

        let pixelBuffer = frame.pixelBuffer
        let context = frame.context
        let sample = LumaSampler.sample(pixelBuffer)

        var frameDelta: Double = 0
        if let grid = sample?.grid {
            if let previous = previousGrid {
                frameDelta = LumaSampler.difference(grid, previous)
            }
            previousGrid = grid
        }

        let lighting = LightingEstimator.evaluate(
            exposure: context.exposure,
            meanLuma: sample?.mean ?? 0.5,
            configuration: configuration
        )
        let motion = motionMonitor.currentReading()
        let stability = StabilityEstimator.evaluate(
            motion: motion,
            frameDelta: frameDelta,
            configuration: configuration
        )
        let faces = detectFaces(in: pixelBuffer, orientation: context.orientation)
        let composition = CompositionEvaluator.evaluate(
            faces: faces,
            isMirrored: context.isMirrored,
            previous: previousComposition,
            configuration: configuration,
            subjectPolicy: subjectPolicy,
            target: compositionTarget
        )
        // Full-body framing is the only thing that needs joints, and it is the
        // most expensive pass here, so it runs only when the mode asks.
        let body = usesBodyPose
            ? bodyPoseAnalyzer.analyze(pixelBuffer: pixelBuffer, orientation: context.orientation)
            : nil
        let level = LevelEstimator.evaluate(
            motion: motion,
            orientation: context.orientation,
            previous: previousLevel,
            configuration: configuration
        )
        let quality = ShotQualityModel.evaluate(
            lighting: lighting,
            stability: stability,
            faces: faces,
            composition: composition,
            level: level,
            configuration: configuration
        )
        previousComposition = composition
        previousLevel = level

        continuation.yield(
            FrameAnalysis(
                timestamp: context.timestamp,
                lighting: lighting,
                stability: stability,
                faces: faces,
                composition: composition,
                isMirrored: context.isMirrored,
                level: level,
                quality: quality,
                body: body
            )
        )
    }

    // MARK: - Vision

    private func detectFaces(
        in pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation
    ) -> [DetectedFace] {
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: orientation,
            options: [:]
        )
        do {
            try handler.perform([faceRequest])
        } catch {
            return []
        }

        let observations = faceRequest.results ?? []
        // Largest first: the guidance layer treats face 0 as the subject.
        return observations
            .sorted { $0.boundingBox.height > $1.boundingBox.height }
            .enumerated()
            .map { index, observation in
                DetectedFace(
                    id: index,
                    boundingBox: observation.boundingBox,
                    roll: observation.roll?.doubleValue,
                    yaw: observation.yaw?.doubleValue,
                    confidence: observation.confidence
                )
            }
    }
}
