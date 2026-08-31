//
//  RuleOfThirdsGrid.swift
//  CameraApp
//
//  A composition aid that should be felt more than seen.
//

import SwiftUI

struct RuleOfThirdsGrid: View {

    var lineWidth: CGFloat = 0.5
    var opacity: Double = 0.32

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            Path { path in
                for column in 1..<3 {
                    let x = size.width * CGFloat(column) / 3
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
                for row in 1..<3 {
                    let y = size.height * CGFloat(row) / 3
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
            }
            .stroke(Color.white.opacity(opacity), lineWidth: lineWidth)
            .shadow(color: .black.opacity(0.25), radius: 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
