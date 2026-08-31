//
//  CameraPreviewView.swift
//  CameraApp
//
//  The live preview: a UIView whose backing layer *is* the capture preview
//  layer, so frames go straight from AVFoundation to the compositor without
//  passing through SwiftUI.
//

import AVFoundation
import SwiftUI
import UIKit

final class CameraPreviewUIView: UIView {

    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        // Safe by construction: `layerClass` guarantees the type.
        layer as! AVCaptureVideoPreviewLayer
    }

    init(session: AVCaptureSession) {
        super.init(frame: .zero)
        backgroundColor = .black
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }
}

/// Owns the preview layer on behalf of the model: coordinate conversion and
/// rotation both need the layer, and both have to happen on the main actor.
@MainActor
final class PreviewController {

    private(set) weak var previewView: CameraPreviewUIView?

    /// Called once the preview layer exists, so the model can build its
    /// rotation coordinator against it.
    var onAttach: (() -> Void)?

    var previewLayer: AVCaptureVideoPreviewLayer? { previewView?.previewLayer }

    func attach(_ view: CameraPreviewUIView) {
        previewView = view
        // Announce on the next main-actor turn: attaching happens during
        // SwiftUI's view update, and the model reacts by mutating observable
        // state, which must not happen mid-update.
        Task { @MainActor [weak self] in
            self?.onAttach?()
        }
    }

    /// Converts a tap in the preview's coordinate space into the device's
    /// point-of-interest space, honouring video gravity and mirroring.
    func devicePoint(for layerPoint: CGPoint) -> CGPoint? {
        guard let previewLayer else { return nil }
        let point = previewLayer.captureDevicePointConverted(fromLayerPoint: layerPoint)
        guard point.x.isFinite, point.y.isFinite else { return nil }
        return CGPoint(
            x: min(max(point.x, 0), 1),
            y: min(max(point.y, 0), 1)
        )
    }

    /// Applies the horizon-level preview angle reported by the rotation
    /// coordinator.
    func setRotationAngle(_ angle: CGFloat) {
        guard let connection = previewLayer?.connection,
              connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }
}

struct CameraPreview: UIViewRepresentable {

    let session: AVCaptureSession
    let controller: PreviewController

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView(session: session)
        controller.attach(view)
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {}
}
