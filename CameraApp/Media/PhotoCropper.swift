//
//  PhotoCropper.swift
//  CameraApp
//
//  Turns the sensor's native-aspect capture into the 9:16 frame the user
//  actually saw. The crop always ships as a new, re-encoded image — the
//  original bytes never leave this call, so nothing uncropped reaches Photos.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum PhotoCropper {

    /// Decodes, crops to `aspectRatio` and re-encodes. Runs synchronously —
    /// callers already hop off the main actor for this, matching every other
    /// full-resolution decode in the capture pipeline.
    ///
    /// Falls back to the original photo untouched if decoding or encoding
    /// fails, so a crop that cannot be performed never costs the user their
    /// shot.
    static func cropToTargetAspect(
        _ photo: CapturedPhoto,
        aspectRatio: Double = AspectCrop.verticalTargetRatio
    ) -> CapturedPhoto {
        guard let source = CGImageSourceCreateWithData(photo.data as CFData, nil) else { return photo }

        // A thumbnail request this large simply returns the full-resolution
        // image — but, unlike decoding the image directly, it also bakes the
        // EXIF orientation into the pixels, so the crop math below can work
        // in plain upright coordinates.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 8192
        ]
        guard let upright = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return photo
        }

        let size = CGSize(width: upright.width, height: upright.height)
        let cropRect = AspectCrop.rect(for: size, targetAspectRatio: aspectRatio)
        guard cropRect.width > 0, cropRect.height > 0,
              let cropped = upright.cropping(to: cropRect) else {
            return photo
        }

        let type = photo.uniformTypeIdentifier.flatMap(UTType.init) ?? .heic
        guard let data = encode(cropped, as: type) else { return photo }

        return CapturedPhoto(
            data: data,
            uniformTypeIdentifier: type.identifier,
            isMirrored: photo.isMirrored
        )
    }

    private static func encode(_ image: CGImage, as type: UTType) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            return nil
        }
        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.92]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
