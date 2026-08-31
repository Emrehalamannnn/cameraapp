//
//  PreviewGeometry.swift
//  CameraApp
//
//  Maps normalised analysis rectangles onto the aspect-filled preview.
//
//  Deliberately independent of AVFoundation's own conversion helpers: the
//  analysis layer already reports face boxes in as-displayed space (mirrored
//  for the front camera), so applying the preview connection's mirroring a
//  second time would flip them back.
//

import CoreGraphics
import Foundation

struct PreviewGeometry: Equatable {

    var viewSize: CGSize
    /// Width ÷ height of the preview content, as displayed upright.
    var contentAspectRatio: Double

    var isValid: Bool {
        viewSize.width > 0 && viewSize.height > 0 && contentAspectRatio > 0
    }

    /// Size of the video content after `.resizeAspectFill`, which may overflow
    /// the view on one axis.
    var filledContentSize: CGSize {
        guard isValid else { return .zero }
        let aspect = CGFloat(contentAspectRatio)
        let scale = max(viewSize.width / aspect, viewSize.height)
        return CGSize(width: aspect * scale, height: scale)
    }

    /// Converts a Vision-style rectangle (normalised, origin bottom-left) into
    /// the preview's coordinate space (origin top-left).
    func rect(forNormalized rect: CGRect) -> CGRect {
        guard isValid else { return .zero }
        let content = filledContentSize
        let originX = (viewSize.width - content.width) / 2
        let originY = (viewSize.height - content.height) / 2
        return CGRect(
            x: originX + rect.minX * content.width,
            y: originY + (1 - rect.maxY) * content.height,
            width: rect.width * content.width,
            height: rect.height * content.height
        )
    }
}
