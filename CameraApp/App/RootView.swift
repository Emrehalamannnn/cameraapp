//
//  RootView.swift
//  CameraApp
//
//  Owns the two screens that sit on top of the camera — settings and the
//  paywall — so the camera view itself stays about taking photos.
//

import SwiftUI

struct RootView: View {

    let model: CameraModel
    let settings: CameraSettings
    let subscription: SubscriptionService

    @State private var isShowingSettings = false
    @State private var isShowingPaywall = false

    var body: some View {
        CameraView(model: model) { isShowingSettings = true }
            .sheet(isPresented: $isShowingSettings, onDismiss: applySettings) {
                SettingsView(settings: settings, subscription: subscription) {
                    isShowingSettings = false
                }
            }
            .fullScreenCover(isPresented: $isShowingPaywall, onDismiss: applySettings) {
                PaywallView(service: subscription) { isShowingPaywall = false }
            }
            .task { await subscription.start() }
            // The offer waits for the camera to be up. Asking for money over a
            // black screen — before the permission prompt has even been
            // answered — is how a camera app gets deleted before it has taken
            // a photo. If the store never answers, it still appears: the
            // fallback prices are honest about what a subscription costs.
            .onChange(of: model.status) { _, status in
                guard status.isRunning, !settings.hasSeenPaywall else { return }
                settings.hasSeenPaywall = true
                if !subscription.isPro {
                    isShowingPaywall = true
                }
            }
            // A locked control was tapped somewhere in the camera UI.
            .onChange(of: model.isPaywallPresented) { _, isPresented in
                guard isPresented else { return }
                model.dismissPaywall()
                if isShowingSettings {
                    // Settings presents its own paywall; two at once is a bug.
                    return
                }
                isShowingPaywall = true
            }
            // Entitlement can change while the app is open — a purchase, a
            // restore, or a lapse — and the capture session has to follow.
            .onChange(of: subscription.status) { _, _ in applySettings() }
    }

    private func applySettings() {
        Task { await model.applySettings() }
    }
}
