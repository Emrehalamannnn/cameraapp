//
//  Haptics.swift
//  CameraApp
//
//  Small, deliberate feedback. The Ready signal fires once per transition —
//  never repeatedly while the shot stays good.
//

import UIKit

@MainActor
final class Haptics {

    static let shared = Haptics()

    private let ready = UIImpactFeedbackGenerator(style: .soft)
    private let shutter = UIImpactFeedbackGenerator(style: .medium)
    private let selection = UISelectionFeedbackGenerator()

    /// Mirrors the Haptics preference. Kept here rather than checked at every
    /// call site: a guard repeated at twenty call sites is a guard that will
    /// eventually be forgotten at the twenty-first.
    var isEnabled = true

    private init() {}

    /// Warms up the Taptic Engine so the first tap is not late.
    func prepare() {
        guard isEnabled else { return }
        ready.prepare()
        shutter.prepare()
        selection.prepare()
    }

    func readySignal() {
        guard isEnabled else { return }
        ready.impactOccurred(intensity: 0.85)
        ready.prepare()
    }

    func shutterSignal() {
        guard isEnabled else { return }
        shutter.impactOccurred()
        shutter.prepare()
    }

    func selectionSignal() {
        guard isEnabled else { return }
        selection.selectionChanged()
        selection.prepare()
    }
}
