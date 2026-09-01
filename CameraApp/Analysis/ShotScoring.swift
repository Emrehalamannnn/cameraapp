//
//  ShotScoring.swift
//  CameraApp
//
//  Picking the keeper out of a burst.
//
//  Two signals, both on-device and both cheap enough to run on a handful of
//  frames right after the shutter:
//
//  * Sharpness, as the variance of a Laplacian over a downscaled grey copy.
//    Motion blur and missed focus both flatten high-frequency detail, so this
//    one number separates a smeared frame from a crisp one.
//  * Face capture quality, from Vision's own `VNDetectFaceCaptureQualityRequest`,
//    which is trained for exactly this question — eyes open, neutral-or-better
//    expression, face not blurred. Using Apple's model beats inventing an
//    eye-aspect-ratio heuristic that would need its own calibration.
//
//  Nothing leaves the device, and nothing is uploaded.
//

import CoreGraphics
import Foundation
import Vision

/// What one frame of a burst is worth.
struct ShotScore: Sendable, Equatable, Identifiable {
    /// Position in the burst, oldest first.
    var id: Int
    /// Laplacian variance, normalised to `0...1`. Higher is sharper.
    var sharpness: Double
    /// Mean Vision face-capture quality across detected faces, `0...1`.
    /// `nil` when the frame contains no face, which is normal for scene modes.
    var faceQuality: Double?

    /// Overall keeper score in `0...1`.
    ///
    /// With a face present its quality dominates, because a razor-sharp photo
    /// of someone blinking is not the one you want. Without a face, sharpness
    /// is all there is to go on.
    var overall: Double {
        guard let faceQuality else { return sharpness }
        return faceQuality * 0.65 + sharpness * 0.35
    }
}

enum BestShotSelector {

    /// Ranks a burst best-first and returns at most `limit` frames.
    ///
    /// Ties break towards the earlier frame: it is the one the user actually
    /// pressed the shutter for.
    static func rank(_ scores: [ShotScore], limit: Int = 3) -> [ShotScore] {
        guard limit > 0 else { return [] }
        let ranked = scores.enumerated().sorted { lhs, rhs in
            if lhs.element.overall == rhs.element.overall {
                return lhs.offset < rhs.offset
            }
            return lhs.element.overall > rhs.element.overall
        }
        return ranked.prefix(limit).map(\.element)
    }

    /// The single keeper.
    static func best(_ scores: [ShotScore]) -> ShotScore? {
        rank(scores, limit: 1).first
    }
}

// MARK: - Measurement

enum ShotScorer {

    /// Longest edge the scoring copy is reduced to. Small enough to score a
    /// burst quickly, large enough that blur still shows up.
    static let scoringDimension = 1024

    /// Variance of a Laplacian over an 8-bit grey image, normalised to `0...1`.
    ///
    /// Exposed separately from the image plumbing so the maths can be tested
    /// against synthesised buffers rather than photographs.
    static func sharpness(
        grayPixels: [UInt8],
        width: Int,
        height: Int
    ) -> Double {
        guard width > 2, height > 2, grayPixels.count >= width * height else { return 0 }

        var sum = 0.0
        var sumOfSquares = 0.0
        var count = 0.0

        for y in 1..<(height - 1) {
            let row = y * width
            let above = row - width
            let below = row + width
            for x in 1..<(width - 1) {
                let laplacian =
                    Double(grayPixels[above + x])
                    + Double(grayPixels[below + x])
                    + Double(grayPixels[row + x - 1])
                    + Double(grayPixels[row + x + 1])
                    - 4 * Double(grayPixels[row + x])
                sum += laplacian
                sumOfSquares += laplacian * laplacian
                count += 1
            }
        }

        guard count > 0 else { return 0 }
        let mean = sum / count
        let variance = max(0, sumOfSquares / count - mean * mean)

        // A variance around 600 is already a crisply focused frame; the curve
        // saturates well before that so small differences near the top stop
        // mattering.
        return min(1, (variance / 600).squareRoot())
    }

    /// Mean face-capture quality across the faces Vision can find.
    static func faceQuality(for image: CGImage) -> Double? {
        let request = VNDetectFaceCaptureQualityRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        let qualities = (request.results ?? []).compactMap { $0.faceCaptureQuality.map(Double.init) }
        guard !qualities.isEmpty else { return nil }
        return qualities.reduce(0, +) / Double(qualities.count)
    }

    /// Renders an image into an 8-bit grey buffer for the sharpness pass.
    static func grayPixels(for image: CGImage) -> (pixels: [UInt8], width: Int, height: Int)? {
        let longest = max(image.width, image.height)
        guard longest > 0 else { return nil }
        let scale = min(1, Double(scoringDimension) / Double(longest))
        let width = max(1, Int(Double(image.width) * scale))
        let height = max(1, Int(Double(image.height) * scale))

        var pixels = [UInt8](repeating: 0, count: width * height)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let success: Bool = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let context = CGContext(
                      data: base,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: width,
                      space: colorSpace,
                      bitmapInfo: CGImageAlphaInfo.none.rawValue
                  ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard success else { return nil }
        return (pixels, width, height)
    }

    /// Scores one frame of a burst.
    static func score(image: CGImage, index: Int) -> ShotScore {
        let sharpnessValue: Double
        if let gray = grayPixels(for: image) {
            sharpnessValue = sharpness(
                grayPixels: gray.pixels,
                width: gray.width,
                height: gray.height
            )
        } else {
            sharpnessValue = 0
        }
        return ShotScore(
            id: index,
            sharpness: sharpnessValue,
            faceQuality: faceQuality(for: image)
        )
    }
}
