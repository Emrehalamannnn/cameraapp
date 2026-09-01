//
//  MediaLibraryService.swift
//  CameraApp
//
//  The only place that talks to PhotoKit.
//
//  The app asks for *add-only* access: it writes photos and never reads the
//  user's library, which is the narrowest permission that does the job.
//

import Foundation
import Photos

actor MediaLibraryService {

    nonisolated var authorizationStatus: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .addOnly)
    }

    nonisolated var isAuthorized: Bool {
        Self.isUsable(authorizationStatus)
    }

    static func isUsable(_ status: PHAuthorizationStatus) -> Bool {
        status == .authorized || status == .limited
    }

    @discardableResult
    func requestAuthorization() async -> PHAuthorizationStatus {
        let current = authorizationStatus
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }

    /// Writes the encoded photo to the library exactly as captured: the same
    /// bytes AVFoundation produced, with its EXIF orientation and metadata intact.
    func save(_ photo: CapturedPhoto) async throws {
        guard Self.isUsable(authorizationStatus) else { throw MediaLibraryError.notAuthorized }

        let data = photo.data
        let uniformTypeIdentifier = photo.uniformTypeIdentifier

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let creationRequest = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.uniformTypeIdentifier = uniformTypeIdentifier
                creationRequest.addResource(with: .photo, data: data, options: options)
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    let message = error?.localizedDescription ?? "The photo could not be saved."
                    continuation.resume(throwing: MediaLibraryError.saveFailed(message))
                }
            }
        }
    }

    /// Imports a finished recording from disk. PhotoKit reads the file
    /// synchronously inside `performChanges`, so by the time this returns
    /// successfully the asset has been copied into the library and the
    /// caller is free to delete the temporary file.
    func saveVideo(at url: URL) async throws {
        guard Self.isUsable(authorizationStatus) else { throw MediaLibraryError.notAuthorized }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let creationRequest = PHAssetCreationRequest.forAsset()
                creationRequest.addResource(with: .video, fileURL: url, options: nil)
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    let message = error?.localizedDescription ?? "The video could not be saved."
                    continuation.resume(throwing: MediaLibraryError.saveFailed(message))
                }
            }
        }
    }
}
