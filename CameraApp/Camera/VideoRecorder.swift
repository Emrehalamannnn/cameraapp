//
//  VideoRecorder.swift
//  CameraApp
//
//  Writes a finished, correctly-oriented, true-9:16 movie file from the raw
//  frames the capture pipeline hands it.
//
//  Built on `AVAssetWriter` rather than `AVCaptureMovieFileOutput` because the
//  crop is the whole point: a movie file output can rotate and mirror a
//  connection, but it cannot crop one, and the sensor's native aspect ratio is
//  wider than the frame the user actually saw. Every frame is re-oriented,
//  cropped to the same rectangle `AspectCrop` computes for photos, scaled to a
//  fixed output size, and appended — audio, when present, is passed straight
//  through.
//
//  An actor because `AVAssetWriter` is not safe to drive from two frame
//  sources at once, and both video and audio frames arrive on their own
//  capture queues.
//

import AVFoundation
import CoreImage
import CoreMedia
import CoreVideo
import Foundation

actor VideoRecorder {

    enum State: Equatable {
        case idle
        case recording
        case finishing
    }

    /// A fixed 1080×1920 output regardless of sensor resolution: predictable
    /// file sizes, and every frame — whatever the source format — lands on
    /// the same canvas.
    private static let outputSize = CGSize(width: 1080, height: 1920)

    private(set) var state: State = .idle
    private(set) var elapsedSeconds: Int = 0

    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var outputURL: URL?
    private var sessionStartTime: CMTime?
    private var hasStartedSession = false
    private var hasAppendedVideoFrame = false

    private let ciContext = CIContext()

    var isRecording: Bool { state == .recording }

    // MARK: - Lifecycle

    /// Starts a new writer. Throws rather than silently ignoring the request
    /// when one is already running, so a caller cannot accidentally start two
    /// recordings into the same file.
    func start(includeAudio: Bool) throws -> URL {
        guard state == .idle else {
            throw CameraError.captureFailed("A recording is already in progress.")
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("capture-\(UUID().uuidString)")
            .appendingPathExtension("mov")

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(Self.outputSize.width),
            AVVideoHeightKey: Int(Self.outputSize.height)
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(videoInput) else {
            throw CameraError.captureFailed("The camera could not start recording.")
        }
        writer.add(videoInput)

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(Self.outputSize.width),
                kCVPixelBufferHeightKey as String: Int(Self.outputSize.height)
            ]
        )

        var audioInput: AVAssetWriterInput?
        if includeAudio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 1,
                AVSampleRateKey: 44_100,
                AVEncoderBitRateKey: 64_000
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            if writer.canAdd(input) {
                writer.add(input)
                audioInput = input
            }
        }

        guard writer.startWriting() else {
            throw CameraError.captureFailed(writer.error?.localizedDescription ?? "The camera could not start recording.")
        }

        self.writer = writer
        self.videoInput = videoInput
        self.audioInput = audioInput
        self.pixelBufferAdaptor = adaptor
        self.outputURL = url
        self.hasStartedSession = false
        self.hasAppendedVideoFrame = false
        self.sessionStartTime = nil
        self.elapsedSeconds = 0
        self.state = .recording
        return url
    }

    // MARK: - Frames

    /// Re-orients, crops, scales and appends one video frame. Silently drops
    /// a frame that arrives while the writer is not ready — that is the
    /// writer's own back-pressure signal, not an error, and dropping one
    /// frame under load is invisible at 30 fps.
    func appendVideo(_ sampleBuffer: CMSampleBuffer, orientation: CGImagePropertyOrientation) {
        guard state == .recording,
              let writer, let videoInput, let adaptor = pixelBufferAdaptor,
              CMSampleBufferDataIsReady(sampleBuffer),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        startSessionIfNeeded(at: timestamp, writer: writer)

        guard videoInput.isReadyForMoreMediaData, let pool = adaptor.pixelBufferPool else { return }
        var outputBuffer: CVPixelBuffer?
        _ = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputBuffer)
        guard let outputBuffer else { return }

        let oriented = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
        let cropRect = AspectCrop
            .rect(for: oriented.extent.size, targetAspectRatio: AspectCrop.verticalTargetRatio)
            .offsetBy(dx: oriented.extent.origin.x, dy: oriented.extent.origin.y)
        let cropped = oriented.cropped(to: cropRect)
        let normalized = cropped.transformed(
            by: CGAffineTransform(translationX: -cropped.extent.origin.x, y: -cropped.extent.origin.y)
        )

        guard normalized.extent.width > 0, normalized.extent.height > 0 else { return }
        let scale = min(
            Self.outputSize.width / normalized.extent.width,
            Self.outputSize.height / normalized.extent.height
        )
        let scaled = normalized.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        ciContext.render(
            scaled,
            to: outputBuffer,
            bounds: CGRect(origin: .zero, size: Self.outputSize),
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        guard adaptor.append(outputBuffer, withPresentationTime: timestamp) else { return }
        hasAppendedVideoFrame = true
        updateElapsed(from: timestamp)
    }

    /// Passes a microphone buffer straight through. No transform is needed —
    /// only the picture was ever cropped.
    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        guard state == .recording, hasStartedSession,
              let audioInput, audioInput.isReadyForMoreMediaData else { return }
        _ = audioInput.append(sampleBuffer)
    }

    private func startSessionIfNeeded(at time: CMTime, writer: AVAssetWriter) {
        guard !hasStartedSession else { return }
        writer.startSession(atSourceTime: time)
        sessionStartTime = time
        hasStartedSession = true
    }

    private func updateElapsed(from time: CMTime) {
        guard let start = sessionStartTime else { return }
        let seconds = CMTimeGetSeconds(CMTimeSubtract(time, start))
        guard seconds.isFinite else { return }
        elapsedSeconds = max(0, Int(seconds))
    }

    // MARK: - Finishing

    /// Finalises the file and returns its URL — or `nil` when nothing usable
    /// was ever captured (an interruption that landed before the first frame,
    /// say), in which case the partial file is removed rather than handed
    /// back for someone to forget to clean up.
    func stop() async -> URL? {
        guard state == .recording, let writer else {
            reset()
            return nil
        }
        state = .finishing
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()

        guard hasStartedSession, hasAppendedVideoFrame else {
            writer.cancelWriting()
            let url = outputURL
            reset()
            if let url { try? FileManager.default.removeItem(at: url) }
            return nil
        }

        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }

        let url = writer.status == .completed ? outputURL : nil
        if url == nil, let outputURL {
            try? FileManager.default.removeItem(at: outputURL)
        }
        reset()
        return url
    }

    private func reset() {
        writer = nil
        videoInput = nil
        audioInput = nil
        pixelBufferAdaptor = nil
        outputURL = nil
        hasStartedSession = false
        hasAppendedVideoFrame = false
        sessionStartTime = nil
        elapsedSeconds = 0
        state = .idle
    }
}
