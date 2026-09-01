//
//  FocusIndicatorView.swift
//  CameraApp
//
//  The square that confirms a tap-to-focus landed.
//

import SwiftUI

struct FocusIndicatorView: View {

    @State private var isSettled = false

    init() {}

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .stroke(Color.yellow.opacity(0.95), lineWidth: 1.2)
            .frame(width: 74, height: 74)
            .overlay(alignment: .center) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(Color.yellow.opacity(0.95), lineWidth: 1.2)
                    .frame(width: 10, height: 10)
                    .opacity(0.7)
            }
            .scaleEffect(isSettled ? 1 : 1.35)
            .opacity(isSettled ? 0.9 : 0)
            .shadow(color: .black.opacity(0.35), radius: 4)
            .onAppear {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                    isSettled = true
                }
            }
            .allowsHitTesting(false)
    }
}

/// The exposure slider that sits beside the focus square, the way the sun does
/// in every phone camera. Only on screen while the square is, because the
/// square is what says which part of the scene is being metered.
struct ExposureSlider: View {

    let bias: Float
    var range: ClosedRange<Float> = -2...2
    let onChange: (Float) -> Void

    private let trackHeight: CGFloat = 132

    /// The value the drag started from, so a slow drag does not accelerate.
    @State private var anchor: Float?

    var body: some View {
        ZStack {
            Capsule()
                .fill(Color.white.opacity(0.28))
                .frame(width: 1.5, height: trackHeight)
                .shadow(color: .black.opacity(0.4), radius: 2)

            Image(systemName: "sun.max.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.yellow.opacity(0.95))
                .shadow(color: .black.opacity(0.5), radius: 3)
                .offset(y: knobOffset)
        }
        .frame(width: 44, height: trackHeight + 26)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let start = anchor ?? bias
                    if anchor == nil { anchor = start }
                    let span = range.upperBound - range.lowerBound
                    let delta = Float(-value.translation.height / trackHeight) * span
                    onChange(min(max(start + delta, range.lowerBound), range.upperBound))
                }
                .onEnded { _ in anchor = nil }
        )
        .accessibilityLabel(Text("Exposure"))
        .accessibilityValue(Text(ExposureFormatter.label(for: bias)))
        .accessibilityAdjustableAction { direction in
            let step: Float = direction == .increment ? 0.1 : -0.1
            onChange(min(max(bias + step, range.lowerBound), range.upperBound))
        }
    }

    private var knobOffset: CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        let midpoint = (range.lowerBound + range.upperBound) / 2
        return CGFloat(-(bias - midpoint) / span) * trackHeight
    }
}

enum ExposureFormatter {
    /// "+0.7 EV" — signed, one decimal, so a correction is never ambiguous.
    static func label(for bias: Float) -> String {
        let rounded = (bias * 10).rounded() / 10
        return String(format: "%+.1f EV", rounded)
    }
}
