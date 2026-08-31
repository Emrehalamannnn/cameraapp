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

    private init() {}

    /// Warms up the Taptic Engine so the first tap is not late.
    func prepare() {
        ready.prepare()
        shutter.prepare()
        selection.prepare()
    }

    func readySignal() {
        ready.impactOccurred(intensity: 0.85)
        ready.prepare()
    }

    func shutterSignal() {
        shutter.impactOccurred()
        shutter.prepare()
    }

    func selectionSignal() {
        selection.selectionChanged()
        selection.prepare()
    }
}
