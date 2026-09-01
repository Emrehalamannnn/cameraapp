//
//  PhotoEnhancer.swift
//  CameraApp
//
//  Optional, conservative, on-device enhancement.
//
//  The design brief for this file is a warning as much as a spec: "make this
//  photo cleaner" is welcome, "AI turned my face into plastic" is not. So there
//  is deliberately no skin smoothing, no face reshaping, no generative fill and
//  no style transfer here. What it does is the set of adjustments a person
//  would make in a photo editor in ten seconds, sized so that the result still
//  looks like the photograph that was taken:
//
//  * lift the exposure only when the frame is genuinely dark
//  * open up shadows and pull back highlights a little
//  * a touch of vibrance, which spares skin tones by design
//  * mild unsharp masking, well short of the halo threshold
//
//  Every amount is clamped, the plan is computed from measured statistics
//  rather than guessed, and the original is never modified — enhancement
//  produces a second set of bytes and the user chooses which to keep.
//
//  Nothing leaves the device.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Measured statistics an enhancement decision is made from.
struct ImageStatistics: Sendable, Equatable {
    /// Mean luma across the frame, `0...1`.
    var meanLuma: Double
    /// Fraction of pixels close to black.
    var shadowClipping: Double
    /// Fraction of pixels close to white.
    var highlightClipping: Double

    static func measure(grayPixels: [UInt8]) -> ImageStatistics {
        guard !grayPixels.isEmpty else {
            return ImageStatistics(meanLuma: 0.5, shadowClipping: 0, highlightClipping: 0)
        }
        var total = 0.0
        var shadows = 0
        var highlights = 0
        for pixel in grayPixels {
            total += Double(pixel)
            if pixel < 12 { shadows += 1 }
            if pixel > 243 { highlights += 1 }
        }
        let count = Double(grayPixels.count)
        return ImageStatistics(
            meanLuma: total / count / 255,
            shadowClipping: Double(shadows) / count,
            highlightClipping: Double(highlights) / count
        )
    }
}

/// How much to adjust, and by how little.
struct EnhancementPlan: Sendable, Equatable {
    /// Exposure in stops. Positive lifts.
    var exposure: Double = 0
    /// Shadow lift, `0...1` in Core Image's scale.
    var shadows: Double = 0
    /// Highlight recovery, where 1 is untouched and lower pulls back.
    var highlights: Double = 1
    /// Vibrance, which leaves already-saturated colours and skin alone.
    var vibrance: Double = 0
    /// Unsharp mask intensity.
    var sharpen: Double = 0

    /// True when the plan would not visibly change the photo, in which case the
    /// app should say so rather than pretending to have improved it.
    var isNoOp: Bool {
        abs(exposure) < 0.02
            && shadows < 0.02
            && highlights > 0.98
            && vibrance < 0.02
            && sharpen < 0.02
    }

    static let none = EnhancementPlan()
}

enum EnhancementPlanner {

    /// Hard ceilings. These are what keep the result looking like a photograph.
    static let maximumExposure = 0.45
    static let maximumShadowLift = 0.35
    static let maximumHighlightRecovery = 0.25
    static let baseVibrance = 0.12
    static let baseSharpen = 0.25

    /// Ideal mean luma. Frames near this are left alone.
    static let targetLuma = 0.46

    static func plan(for statistics: ImageStatistics) -> EnhancementPlan {
        var plan = EnhancementPlan()

        // Exposure: only correct a real miss, and only part of the way. Pulling
        // a photo all the way to a target average is how images start looking
        // processed.
        let lumaError = targetLuma - statistics.meanLuma
        if abs(lumaError) > 0.06 {
            let stops = lumaError * 1.4
            plan.exposure = min(max(stops, -maximumExposure), maximumExposure)
        }

        // Shadows: lift in proportion to how much of the frame is crushed.
        if statistics.shadowClipping > 0.02 {
            plan.shadows = min(statistics.shadowClipping * 2.5, maximumShadowLift)
        }

        // Highlights: recover in proportion to how much is blown.
        if statistics.highlightClipping > 0.015 {
            let recovery = min(statistics.highlightClipping * 2.0, maximumHighlightRecovery)
            plan.highlights = 1 - recovery
        }

        // A small, constant amount of finish. Vibrance rather than saturation
        // because it protects skin tones, and a mild unsharp mask rather than
        // sharpening that would ring on edges.
        plan.vibrance = baseVibrance
        plan.sharpen = baseSharpen

        return plan
    }
}

/// Applies a plan. Kept separate from the planning so the decisions can be
/// tested without a rendering context.
final class PhotoEnhancer {

    private let context: CIContext

    init(context: CIContext = CIContext(options: [.useSoftwareRenderer: false])) {
        self.context = context
    }

    /// Enhances encoded photo data, returning new encoded data.
    ///
    /// - Returns: `nil` when the image cannot be read, or when the plan would
    ///   not meaningfully change it.
    func enhance(data: Data, plan: EnhancementPlan) -> Data? {
        guard !plan.isNoOp, let input = CIImage(data: data) else { return nil }

        var image = input

        if abs(plan.exposure) > 0.001 {
            let filter = CIFilter.exposureAdjust()
            filter.inputImage = image
            filter.ev = Float(plan.exposure)
            image = filter.outputImage ?? image
        }

        if plan.shadows > 0.001 || plan.highlights < 0.999 {
            let filter = CIFilter.highlightShadowAdjust()
            filter.inputImage = image
            filter.shadowAmount = Float(plan.shadows)
            filter.highlightAmount = Float(plan.highlights)
            image = filter.outputImage ?? image
        }

        if plan.vibrance > 0.001 {
            let filter = CIFilter.vibrance()
            filter.inputImage = image
            filter.amount = Float(plan.vibrance)
            image = filter.outputImage ?? image
        }

        if plan.sharpen > 0.001 {
            let filter = CIFilter.unsharpMask()
            filter.inputImage = image
            filter.radius = 1.6
            filter.intensity = Float(plan.sharpen)
            image = filter.outputImage ?? image
        }

        let colorSpace = input.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        return context.heifRepresentation(
            of: image,
            format: .RGBA8,
            colorSpace: colorSpace,
            options: [:]
        ) ?? context.jpegRepresentation(
            of: image,
            colorSpace: colorSpace,
            options: [:]
        )
    }
}
