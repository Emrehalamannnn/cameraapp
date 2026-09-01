//
//  DirectionalCueView.swift
//  CameraApp
//
//  The supplemental arrow for spatial guidance.
//
//  Deliberately small, edge-anchored and semi-transparent: the subject is the
//  point of the screen, and a large arrow across their face would be worse than
//  no arrow at all. The banner text stays authoritative — this just saves the
//  user from having to read it.
//

import SwiftUI

struct DirectionalCueView: View {

    let direction: GuidanceDirection

    @State private var isNudging = false

    private let inset: CGFloat = 28
    private let glyphSize: CGFloat = 26
    private let travel: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            if let symbol = symbolName {
                Image(systemName: symbol)
                    .font(.system(size: glyphSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 1)
                    .offset(nudgeOffset)
                    .position(position(in: proxy.size))
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
                    .onAppear { startNudging() }
                    .onDisappear { isNudging = false }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.easeInOut(duration: 0.25), value: direction)
    }

    // MARK: - Appearance

    private var symbolName: String? {
        switch direction {
        case .left: return "chevron.left"
        case .right: return "chevron.right"
        case .up: return "chevron.up"
        case .down: return "chevron.down"
        // Scale changes read clearly from the banner glyph, and an arrow for
        // them would land squarely on the subject.
        case .closer, .back, .none: return nil
        }
    }

    private func position(in size: CGSize) -> CGPoint {
        switch direction {
        case .left: return CGPoint(x: inset, y: size.height / 2)
        case .right: return CGPoint(x: size.width - inset, y: size.height / 2)
        case .up: return CGPoint(x: size.width / 2, y: size.height * 0.26)
        case .down: return CGPoint(x: size.width / 2, y: size.height * 0.74)
        case .closer, .back, .none: return CGPoint(x: size.width / 2, y: size.height / 2)
        }
    }

    /// A small drift in the direction of travel, which reads as "this way" far
    /// faster than a static glyph does.
    private var nudgeOffset: CGSize {
        guard isNudging else { return .zero }
        switch direction {
        case .left: return CGSize(width: -travel, height: 0)
        case .right: return CGSize(width: travel, height: 0)
        case .up: return CGSize(width: 0, height: -travel)
        case .down: return CGSize(width: 0, height: travel)
        case .closer, .back, .none: return .zero
        }
    }

    private func startNudging() {
        isNudging = false
        withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
            isNudging = true
        }
    }
}
