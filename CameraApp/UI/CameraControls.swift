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

/// The visual half of `GlassCircleButton`, for places that supply their own
/// tap handling — the system photo picker, for instance.
struct GlassCircleLabel: View {

    let systemImage: String
    var isHighlighted: Bool = false
    var diameter: CGFloat = 42
    var rotation: Angle = .zero

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: diameter * 0.38, weight: .semibold))
            .foregroundStyle(isHighlighted ? Color.black : Color.white)
            .rotationEffect(rotation)
            .frame(width: diameter, height: diameter)
            .background {
                Circle().fill(
                    isHighlighted
                        ? AnyShapeStyle(Color.white.opacity(0.92))
                        : AnyShapeStyle(Material.ultraThin)
                )
            }
            .overlay {
                Circle().strokeBorder(
                    Color.white.opacity(isHighlighted ? 0 : 0.12),
                    lineWidth: 0.5
                )
            }
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
    let autoCaptureProgress: Double
    let action: () -> Void

    private static let outerDiameter: CGFloat = 76
    private static let innerDiameter: CGFloat = 62

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(isReady ? Color.readyAccent : Color.white.opacity(0.9), lineWidth: 3)
                    .frame(width: Self.outerDiameter, height: Self.outerDiameter)
                if autoCaptureProgress > 0, !isBusy {
                    Circle()
                        .trim(from: 0, to: min(max(autoCaptureProgress, 0), 1))
                        .stroke(
                            Color.readyAccent,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: Self.outerDiameter, height: Self.outerDiameter)
                        .animation(.linear(duration: 0.1), value: autoCaptureProgress)
                }
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
        .accessibilityHint(
            Text(
                autoCaptureProgress > 0
                    ? "Auto Capture is preparing to take the photo"
                    : (isReady ? "The shot is ready" : "Framing guidance is still adjusting")
            )
        )
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

// MARK: - Shooting mode

/// The mode strip. Text only, no chrome: it sits over the photo, so it earns
/// its place by being small and quiet rather than by being a control panel.
struct ModeSelector: View {

    let modes: [ShootingMode]
    let selected: ShootingMode
    let rotation: Angle
    /// Modes the current subscription does not cover. They stay tappable — the
    /// tap opens the paywall — but they are marked, so nothing looks broken.
    var lockedModes: Set<ShootingMode> = []
    let onSelect: (ShootingMode) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                ForEach(modes) { mode in
                    let isActive = mode == selected
                    let isLocked = lockedModes.contains(mode)
                    Button {
                        onSelect(mode)
                    } label: {
                        HStack(spacing: 3) {
                            if isLocked {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            Text(mode.shortTitle)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .tracking(0.6)
                        }
                        .foregroundStyle(
                            isActive
                                ? Color.yellow
                                : Color.white.opacity(isLocked ? 0.4 : 0.65)
                        )
                        .rotationEffect(rotation)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableButtonStyle(pressedScale: 0.94))
                    .accessibilityLabel(
                        Text(isLocked ? "\(mode.title) mode, Pro" : "\(mode.title) mode")
                    )
                    .accessibilityAddTraits(isActive ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 28)
        }
        .frame(height: 26)
        .animation(.easeOut(duration: 0.2), value: selected)
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

// MARK: - Self-timer

/// The seconds left, large enough to read from across a room — which is where
/// the person who set the timer usually is.
struct CountdownView: View {

    let seconds: Int

    var body: some View {
        Text("\(seconds)")
            .font(.system(size: 120, weight: .thin, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.4), radius: 12)
            .contentTransition(.numericText(countsDown: true))
            .accessibilityLabel(Text("\(seconds) seconds remaining"))
    }
}
