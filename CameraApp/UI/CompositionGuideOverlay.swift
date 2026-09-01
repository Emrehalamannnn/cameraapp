//
//  CompositionGuideOverlay.swift
//  CameraApp
//
//  Draws whichever guide is selected. Hairlines with a faint shadow, so they
//  stay readable over a white wall and a night sky alike without ever being
//  the brightest thing on screen.
//

import SwiftUI

struct CompositionGuideOverlay: View {

    let guide: CompositionGuide

    var body: some View {
        switch guide {
        case .off:
            EmptyView()
        case .thirds:
            RuleOfThirdsGrid()
        case .goldenRatio:
            GuideLines(fractions: [0.382, 0.618])
        case .square:
            SquareCropGuide()
        }
    }
}

/// Vertical and horizontal lines at the given fractions of the frame.
struct GuideLines: View {

    let fractions: [CGFloat]
    var lineWidth: CGFloat = 0.5
    var opacity: Double = 0.32

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            Path { path in
                for fraction in fractions {
                    let x = size.width * fraction
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))

                    let y = size.height * fraction
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

/// A centred square, with everything the crop would discard dimmed.
struct SquareCropGuide: View {

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let side = min(size.width, size.height)
            let square = CGRect(
                x: (size.width - side) / 2,
                y: (size.height - side) / 2,
                width: side,
                height: side
            )

            ZStack {
                // Dim what the crop throws away rather than outlining what it
                // keeps: the eye reads the bright rectangle as the photo.
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: size))
                    path.addRect(square)
                }
                .fill(Color.black.opacity(0.28), style: FillStyle(eoFill: true))

                Path { $0.addRect(square) }
                    .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
