//
//  CapturedPhoto.swift
//  CameraApp
//
//  The encoded photo exactly as the capture pipeline produced it.
//

import Foundation
import UIKit

struct CapturedPhoto: Identifiable, Sendable {
    let id = UUID()
    /// The encoded file (HEIC or JPEG) including EXIF orientation. This is what
    /// gets written to the photo library — it is never re-encoded.
    let data: Data
    let uniformTypeIdentifier: String?
    /// Whether the frame came from the mirrored front-camera preview. Kept for
    /// future enhancement work; capture itself is never mirrored, matching the
    /// system camera's default.
    let isMirrored: Bool

    /// Decodes a display-sized image off the main thread.
    ///
    /// Full-resolution decoding of a 12–48 MP photo is far too slow to do while
    /// the preview is animating, and the review screen only needs screen pixels.
    func makePreviewImage(maxDimension: CGFloat) async -> UIImage? {
        let encoded = data
        return await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let image = UIImage(data: encoded) else { return nil }
            let longestSide = max(image.size.width, image.size.height)
            guard longestSide > maxDimension, longestSide > 0 else {
                return image.preparingForDisplay() ?? image
            }
            let scale = maxDimension / longestSide
            let target = CGSize(
                width: (image.size.width * scale).rounded(),
                height: (image.size.height * scale).rounded()
            )
            return image.preparingThumbnail(of: target) ?? image
        }.value
    }
}
