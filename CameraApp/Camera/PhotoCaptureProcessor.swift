//
//  PhotoCaptureProcessor.swift
//  CameraApp
//
//  Bridges AVCapturePhotoOutput's delegate callbacks to async/await.
//
//  AVFoundation calls back on its own queue and only holds the delegate for the
//  life of the capture, so the processor keeps itself alive until the capture
//  finishes and resumes its continuation exactly once.
//

import AVFoundation
import Foundation

final class PhotoCaptureProcessor: NSObject, AVCapturePhotoCaptureDelegate {

    private let lock = NSLock()
    private var continuation: CheckedContinuation<CapturedPhoto, Error>?
    private var retainedSelf: PhotoCaptureProcessor?
    private var photoData: Data?
    private let uniformTypeIdentifier: String?
    private let isMirrored: Bool

    /// - Parameters:
    ///   - uniformTypeIdentifier: the container type of the encoded photo (HEIC
    ///     or JPEG), forwarded to PhotoKit so the asset resource is typed correctly.
    init(uniformTypeIdentifier: String?, isMirrored: Bool) {
        self.uniformTypeIdentifier = uniformTypeIdentifier
        self.isMirrored = isMirrored
        super.init()
    }

    func capture(
        with settings: AVCapturePhotoSettings,
        using output: AVCapturePhotoOutput
    ) async throws -> CapturedPhoto {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            self.retainedSelf = self
            lock.unlock()
            output.capturePhoto(with: settings, delegate: self)
        }
    }

    // MARK: - AVCapturePhotoCaptureDelegate

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            finish(with: .failure(CameraError.captureFailed(error.localizedDescription)))
            return
        }
        // `fileDataRepresentation()` keeps the encoder's own output — full
        // resolution, original EXIF, correct orientation. No re-encode.
        photoData = photo.fileDataRepresentation()
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        if let error {
            finish(with: .failure(CameraError.captureFailed(error.localizedDescription)))
            return
        }
        guard let photoData else {
            finish(with: .failure(CameraError.photoDataUnavailable))
            return
        }
        finish(
            with: .success(
                CapturedPhoto(
                    data: photoData,
                    uniformTypeIdentifier: uniformTypeIdentifier,
                    isMirrored: isMirrored
                )
            )
        )
    }

    // MARK: - Completion

    private func finish(with result: Result<CapturedPhoto, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        continuation?.resume(with: result)

        // Release the self-reference on a later turn of the run loop so the
        // object cannot be deallocated while AVFoundation is still inside a
        // delegate callback on it.
        DispatchQueue.main.async { [self] in
            retainedSelf = nil
        }
    }
}
