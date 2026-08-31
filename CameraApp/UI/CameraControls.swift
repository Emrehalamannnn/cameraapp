//
//  CameraControls.swift
//  CameraApp
//
//  Translucent, restrained controls. The photo is the interface; these sit on
//  top of it as lightly as possible.
//

import SwiftUI

// MARK: - Round glass button

struct GlassCircleButton: View {

    let systemImage: String
    let accessibilityLabel: String
    var isHighlighted: Bool = false
    var diameter: CGFloat = 42
    var rotation: Angle = .zero
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: diameter * 0.38, weight: .semibold))
                .foregroundStyle(isHighlighted ? Color.black : Color.white)
                .rotationEffect(rotation)
                .frame(width: diameter, height: diameter)
                .background {
                    Circle()
                        .fill(isHighlighted ? AnyShapeStyle(Color.white.opacity(0.92)) : AnyShapeStyle(Material.ultraThin))
                }
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(isHighlighted ? 0 : 0.12), lineWidth: 0.5)
                }
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text(accessibilityLabel))
    }
}

struct PressableButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.9

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

// MARK: - Shutter

struct ShutterButton: View {

    let isReady: Bool
    let isBusy: Bool
    let isEnabled: Bool
    let action: () -> Void

    private static let outerDiameter: CGFloat = 76
    private static let innerDiameter: CGFloat = 62

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(isReady ? Color.readyAccent : Color.white.opacity(0.9), lineWidth: 3)
                    .frame(width: Self.outerDiameter, height: Self.outerDiameter)
                Circle()
                    .fill(Color.white)
                    .frame(width: Self.innerDiameter, height: Self.innerDiameter)
                    .scaleEffect(isBusy ? 0.82 : 1)
                if isBusy {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.black)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isReady)
            .animation(.easeOut(duration: 0.18), value: isBusy)
        }
        .buttonStyle(PressableButtonStyle(pressedScale: 0.93))
        .disabled(!isEnabled || isBusy)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityLabel(Text("Take photo"))
        .accessibilityHint(Text(isReady ? "The shot is ready" : "Framing guidance is still adjusting"))
    }
}

// MARK: - Zoom

struct ZoomSelector: View {

    let options: [Double]
    let currentZoom: Double
    let rotation: Angle
    let onSelect: (Double) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                let isActive = option == activeOption
                Button {
                    onSelect(option)
                } label: {
                    Text(label(for: option, isActive: isActive))
                        .font(.system(size: isActive ? 13 : 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(isActive ? Color.yellow : Color.white)
                        .monospacedDigit()
                        .frame(minWidth: 38)
                        .frame(height: 38)
                        .background {
                            Circle()
                                .fill(Color.white.opacity(isActive ? 0.16 : 0))
                                .frame(width: 38, height: 38)
                        }
                        .rotationEffect(rotation)
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(Text("\(ZoomCapabilities.label(for: option)) zoom"))
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background {
            Capsule(style: .continuous).fill(.ultraThinMaterial)
        }
        .overlay {
            Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        }
        .animation(.easeOut(duration: 0.2), value: activeOption)
    }

    /// The preset closest to the live zoom factor, which carries the live value
    /// while the user is pinching between stops.
    private var activeOption: Double? {
        options.min { abs($0 - currentZoom) < abs($1 - currentZoom) }
    }

    private func label(for option: Double, isActive: Bool) -> String {
        isActive ? ZoomCapabilities.label(for: currentZoom) : ZoomCapabilities.label(for: option)
    }
}

// MARK: - Transient message

struct MessageToast: View {

    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background {
                Capsule(style: .continuous).fill(.ultraThinMaterial)
            }
            .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}
