//
//  LevelIndicatorView.swift
//  CameraApp
//
//  Appears only while level guidance is the single active instruction.
//

import SwiftUI

struct LevelIndicatorView: View {
    let rollDegrees: Double
    let rotation: Angle

    var body: some View {
        ZStack {
            Capsule()
                .fill(Color.white.opacity(0.3))
                .frame(width: 52, height: 2)
            Capsule()
                .fill(Color.white)
                .frame(width: 34, height: 2)
                .rotationEffect(.degrees(rollDegrees))
        }
        .frame(width: 62, height: 22)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay {
            Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        }
        .rotationEffect(rotation)
        .animation(.easeOut(duration: 0.16), value: rollDegrees)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
