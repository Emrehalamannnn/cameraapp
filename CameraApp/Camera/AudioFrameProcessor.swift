//
//  AudioFrameProcessor.swift
//  CameraApp
//
//  A thin pass-through from the microphone's sample buffer delegate to
//  whoever is currently recording. It exists at all only so `CaptureService`
//  has a delegate object to hand `AVCaptureAudioDataOutput` — the routing
//  decision belongs to the caller, not to this class.
//

import AVFoundation
import Foundation

/// `@unchecked Sendable`: `sink` is only ever read on `queue`, and only ever
/// written via `setSink`, which itself hops onto `queue` before mutating it.
final class AudioFrameProcessor: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {

    let queue = DispatchQueue(label: "com.cameraapp.audio-frames", qos: .userInitiated)

    private var sink: (@Sendable (CMSampleBuffer) -> Void)?

    func setSink(_ sink: (@Sendable (CMSampleBuffer) -> Void)?) {
        queue.async { [self] in
            self.sink = sink
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        sink?(sampleBuffer)
    }
}
