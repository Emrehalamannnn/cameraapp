//
//  DebugOverlayView.swift
//  CameraApp
//
//  Calibration instrument for tuning the composition thresholds on a real
//  phone, where the numbers actually have to earn their keep.
//
//  The entire file is behind `#if DEBUG` and the only way to switch it on is a
//  long press that is itself compiled out of Release builds. Nothing here can
//  reach a shipping app.
//

#if DEBUG

import SwiftUI

struct DebugOverlayView: View {

    let quality: ShotQualityAssessment
    let composition: CompositionAssessment
    let level: LevelAssessment
    let faces: [DetectedFace]
    let geometry: PreviewGeometry
    let configuration: AnalysisConfiguration
    let subscription: SubscriptionService

    var body: some View {
        ZStack(alignment: .topLeading) {
            compositionRegions
            boxes
            readout
            testPremiumToggle
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The regions the rules actually test against: the horizontal dead zone
    /// and the headroom ceiling.
    private var compositionRegions: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Rectangle()
                    .stroke(Color.cyan.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .frame(
                        width: size.width * CGFloat(configuration.horizontalEnterTolerance),
                        height: size.height
                    )
                    .position(x: size.width / 2, y: size.height / 2)

                Rectangle()
                    .fill(Color.orange.opacity(0.1))
                    .frame(
                        width: size.width,
                        height: size.height * CGFloat(configuration.maximumHeadroom)
                    )
                    .position(
                        x: size.width / 2,
                        y: size.height * CGFloat(configuration.maximumHeadroom) / 2
                    )
            }
        }
    }

    private var boxes: some View {
        ZStack(alignment: .topLeading) {
            ForEach(faces) { face in
                let rect = geometry.rect(forNormalized: face.boundingBox)
                if rect.width > 1 {
                    Rectangle()
                        .stroke(Color.green.opacity(0.9), lineWidth: 1)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
            if let subject = composition.subjectBox {
                let rect = geometry.rect(forNormalized: subject)
                Rectangle()
                    .stroke(Color.yellow.opacity(0.9), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
    }

    private var readout: some View {
        VStack(alignment: .leading, spacing: 2) {
            row("score", "\(quality.score)  \(describe(quality.severity))")
            row("ready", quality.isReady ? "YES" : "no")
            row("state", describe(composition.state))
            row("offset", number(composition.horizontalOffset))
            row("fill", number(composition.subjectFill))
            row("headroom", number(composition.headroom))
            row("edge", number(composition.edgeClearance))
            row("conf", number(Double(composition.detectionConfidence)))
            row("roll", level.state == .unavailable ? "n/a" : "\(number(level.rollDegrees))°")
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .foregroundStyle(.white)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.55)))
        .padding(.leading, 12)
        .padding(.top, 100)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label).foregroundStyle(.white.opacity(0.55))
            Text(value)
        }
    }

    private func number(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func describe(_ severity: ShotQualitySeverity) -> String {
        switch severity {
        case .critical: return "critical"
        case .correctable: return "correctable"
        case .good: return "good"
        }
    }

    /// Development/testing only — flips `DebugPremiumOverride`. The rest of
    /// this overlay is display-only and deliberately not hit-testable; this
    /// is the one control that needs to be.
    private var testPremiumToggle: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    subscription.debugToggleTestPremium()
                } label: {
                    Text(subscription.status.isPro ? "TEST PRO: ON" : "TEST PRO: OFF")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(subscription.status.isPro ? Color.yellow : Color.white.opacity(0.7)))
                }
                .allowsHitTesting(true)
                .padding(.trailing, 16)
                .padding(.bottom, 140)
            }
        }
    }

    private func describe(_ state: CompositionState) -> String {
        switch state {
        case .noSubject: return "noSubject"
        case .balanced: return "balanced"
        case .subjectTooClose: return "tooClose"
        case .subjectTooFar: return "tooFar"
        case .offCenter(let nudge): return "offCenter(\(nudge))"
        case .excessiveHeadroom: return "excessHeadroom"
        case .insufficientHeadroom: return "lowHeadroom"
        case .dangerousEdge: return "dangerousEdge"
        }
    }
}

#endif
