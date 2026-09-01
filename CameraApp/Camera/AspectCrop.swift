//
//  AspectCrop.swift
//  CameraApp
//
//  The single piece of geometry behind the app's vertical framing: what
//  "true 9:16" means in pixels, and where to draw the line when a sensor's
//  native aspect ratio does not match it.
//
//  Every consumer — the live preview, the saved photo, every recorded video
//  frame — calls the same function, so what gets saved is provably what was
//  on screen rather than three independent approximations of it.
//

import CoreGraphics
import Foundation

enum AspectCrop {

    /// Width ÷ height for the app's primary capture frame.
    static let verticalTargetRatio: Double = 9.0 / 16.0

    /// The centred crop rect, in the same units as `size`, that turns an
    /// image of `size` into `targetAspectRatio` without stretching.
    ///
    /// The narrower axis is always kept at full size; only the wider one is
    /// trimmed, equally from both edges. This is the same rule
    /// `.resizeAspectFill` uses to fill a layer, so a crop computed here
    /// matches what the preview already shows.
    static func rect(for size: CGSize, targetAspectRatio: Double = verticalTargetRatio) -> CGRect {
        guard size.width > 0, size.height > 0, targetAspectRatio > 0 else {
            return CGRect(origin: .zero, size: size)
        }
        let currentRatio = size.width / size.height
        let target = CGFloat(targetAspectRatio)

        if currentRatio > target {
            // Wider than the target: crop the sides, keep full height.
            let width = (size.height * target).rounded()
            let x = ((size.width - width) / 2).rounded()
            return CGRect(x: x, y: 0, width: width, height: size.height)
        } else if currentRatio < target {
            // Taller than the target: crop top and bottom, keep full width.
            let height = (size.width / target).rounded()
            let y = ((size.height - height) / 2).rounded()
            return CGRect(x: 0, y: y, width: size.width, height: height)
        } else {
            return CGRect(origin: .zero, size: size)
        }
    }
}

extension CGSize {
    /// The largest 9:16 rectangle that fits centred within this size,
    /// letterboxed on whichever axis has room to spare.
    ///
    /// The screen itself is never assumed to already be 9:16 — an iPhone's
    /// display is usually taller, so this fills the width and leaves space
    /// above and below for the letterbox rather than stretching the frame
    /// to match the glass.
    func nineSixteenBox(targetAspectRatio: Double = AspectCrop.verticalTargetRatio) -> CGRect {
        guard width > 0, height > 0, targetAspectRatio > 0 else { return .zero }
        let target = CGFloat(targetAspectRatio)

        let widthConstrained = CGSize(width: width, height: width / target)
        let box: CGSize
        if widthConstrained.height <= height {
            box = widthConstrained
        } else {
            box = CGSize(width: height * target, height: height)
        }
        let origin = CGPoint(x: (width - box.width) / 2, y: (height - box.height) / 2)
        return CGRect(origin: origin, size: box)
    }
}
