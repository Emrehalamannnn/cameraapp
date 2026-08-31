//
//  GuidanceBanner.swift
//  CameraApp
//
//  One instruction. Never two, never a debug readout.
//

import SwiftUI

struct GuidanceBanner: View {

    let state: GuidanceState?
    let rotation: Angle

    var body: some View {
        Group {
            if let state {
                HStack(spacing: 7) {
                    Image(systemName: symbolName(for: state.message))
                        .font(.system(size: 13, weight: .bold))
                        .transition(.opacity)
                    Text(state.message.rawValue)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundStyle(state.isReady ? Color.black : Color.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background {
                    Capsule(style: .continuous)
                        .fill(state.isReady ? AnyShapeStyle(Color.readyAccent) : AnyShapeStyle(Material.ultraThin))
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(state.isReady ? 0 : 0.14), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.28), radius: 10, y: 3)
                .rotationEffect(rotation)
                .scaleEffect(state.isReady ? 1.04 : 1)
                .id(state.message)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.92)),
                        removal: .opacity
                    )
                )
                .accessibilityLabel(Text(state.message.rawValue))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: state)
    }

    private func symbolName(for message: GuidanceMessage) -> String {
        switch message {
        case .ready: return "checkmark.circle.fill"
        case .moreLight: return "sun.max.fill"
        case .tooMuchLight: return "exclamationmark.triangle.fill"
        case .holdStill: return "hand.raised.fill"
        case .stepBack: return "arrow.up.left.and.arrow.down.right"
        case .moveCloser: return "arrow.down.right.and.arrow.up.left"
        case .moveLeft: return "arrow.left"
        case .moveRight: return "arrow.right"
        }
    }
}

extension Color {
    /// The single accent in the app: used only to say "this shot is good".
    static let readyAccent = Color(red: 0.61, green: 0.94, blue: 0.55)
}
