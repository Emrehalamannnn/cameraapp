//
//  SubjectOverlay.swift
//  CameraApp
//
//  Draws where the camera thinks the subject is. Restrained on purpose: a thin
//  bracket on the primary face, nothing on the rest.
//

import SwiftUI

struct SubjectOverlay: View {

    let faces: [DetectedFace]
    let geometry: PreviewGeometry
    let isReady: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(faces) { face in
                let rect = geometry.rect(forNormalized: face.boundingBox)
                if rect.width > 1, rect.height > 1 {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            (isReady && face.id == 0) ? Color.readyAccent : Color.white.opacity(0.85),
                            lineWidth: face.id == 0 ? 1.4 : 1
                        )
                        .opacity(face.id == 0 ? 1 : 0.45)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .shadow(color: .black.opacity(0.3), radius: 3)
                }
            }
        }
        .animation(.easeOut(duration: 0.18), value: faces)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
